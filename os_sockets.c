//OHHRPGCE COMMON - Berkeley socket-based networking routines (Windows and Unix)
//Please read LICENSE.txt for GNU GPL License details and disclaimer of liability

//fb_stub.h MUST be included first, to ensure fb_off_t is 64 bit
#include "fb/fb_stub.h"

#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
  #define WIN32_LEAN_AND_MEAN  // Prevent conflicts due to windows.h including winsock 1 header
  #include <windows.h>
  #include <winsock2.h>
  // The follow two headers are necessary for getaddrinfo to work on pre-WinXP versions
  #include <ws2tcpip.h>
  #include <wspiapi.h>
  #define SHUT_WR SD_SEND
#else
  #include <errno.h>
  #include <sys/types.h>
  #include <sys/socket.h>
  #include <netdb.h>
  typedef int SOCKET;
  #define SOCKET_ERROR -1
  #define INVALID_SOCKET -1
  #define closesocket close
#endif

#include "os.h"
#include "misc.h"


static const char *lasterror() {
#ifdef _WIN32
	return win_error(WSAGetLastError());
#else
	return strerror(errno);
#endif
}

/*****************************************************************************/

typedef struct {
	boolint failed;
	boolint started;     // HTTP_request called, cleanup needed
	char *response;      // Response with the header stripped
	int response_len;    // Length of response, NOT response_buf
	char *response_buf;  // Response with the header
	int status;          // HTTP status, 200 for success
	char *status_string; // Returned from the server, may be anything
} HTTPRequest;


void HTTP_Request_init(HTTPRequest *req) {
	memset(req, 0, sizeof(HTTPRequest));
}

void HTTP_Request_destroy(HTTPRequest *req) {
	if (req->started) return;
	free(req->response_buf);
	req->response_buf = NULL;
	req->response = NULL;
	free(req->status_string);
	req->status_string = NULL;
#ifdef _WIN32
	WSACleanup();
#endif
	req->started = false;
}

static void parse_HTTP_response(HTTPRequest *req) {
	// Find the HTTP result code
	char status_buf[64];
	if (sscanf(req->response_buf, "HTTP/%*d.%*d %d %63[^\r]\r\n", &req->status, status_buf) != 2) {
		debug(errError, "Couldn't parse HTTP header line: %50s", req->response_buf);
		req->failed = true;
		return;
	}
	req->status_string = strdup(status_buf);

	// Trim the header
	char *doubleline = strstr(req->response_buf, "\r\n\r\n");
	if (doubleline) {
		req->response =  doubleline + 4;
		req->response_len -= doubleline + 4 - req->response_buf;
	} else {
		debug(errError, "Couldn't find end of HTTP header");
		req->failed = true;
	}
}

static bool send_on_socket(SOCKET sock, const char *sendbuf, int sendlen, HTTPRequest *req, const char *server) {
	int sent = 0;
	while (sent < sendlen) {
		int result = send(sock, sendbuf + sent, sendlen - sent, 0);
		if (result == SOCKET_ERROR) {
			debug(errError, "send(%s) error: %s", server, lasterror());
			closesocket(sock);
			req->failed = true;
			return false;
		} else {
			sent += result;
		}
	}
	return true;
}

/* Make a HTTP request and receive a response, synchronously.
   -req MUST not be initialised before being passed in, but does have to be destroyed
    afterwards with HTTP_Request_destroy(), whether this function succeeds or not.
   -url can optionally include a protocol
   -verb should be e.g. "GET" or "POST"
   -data should be NULL for GET and the data to include for POST.
   Returns non-zero on success.
*/
boolint HTTP_request(HTTPRequest *req, const char *url, const char *verb, const char *data, int datalen) {
	int result;

	HTTP_Request_init(req);
#ifdef _WIN32
	// Initialise Winsock
	WSADATA wsaData;
	result = WSAStartup(MAKEWORD(2, 2), &wsaData);
	if (result) {
		debug(errError, "WSAStartup failed: %s", win_error(result));
		req->failed = true;
		return false;
	}
#endif
	req->started = true;

	// Split protocol
	const char *url_protosep, *url_server;
	url_protosep = strstr(url, "://");
	url_server = url_protosep ? url_protosep + 3 : url;

	// Split path and server
	char *path, *server;
	path = strchr(url_server, '/');  // Including any query string
	int url_server_len = path ? path - url_server : strlen(url_server);
	if (!path) path = "/";
	server = alloca(url_server_len + 1);
	memcpy(server, url_server, url_server_len);  // The port hasn't been split off yet
	server[url_server_len] = '\0';

	// Split port
	char *port;
	port = strchr(server, ':');
	if (port) {
		*port = '\0';  // Cut the port off the server address
		port++;   // Advance past ':'
	} else if (url_protosep) {  // Use the protocol, e.g. "http"
		int proto_len = url_protosep - url;
		port = alloca(proto_len + 8);
		memcpy(port, url, proto_len);
		port[proto_len] = '\0';
		// Translate from the protocol to a port number. This isn't needed for getaddrinfo,
		// but it is needed for the Host: line in the HTTP header
		struct servent *service = getservbyname(port, "tcp");
		if (service) {
			sprintf(port, "%d", ntohs(service->s_port));
		} else {
			debug(errError, "getservbyname(%s) failed: %s", port, lasterror());
			port = "80";
		}
		//endservent();  // Doesn't exist
	} else {
		port = "80";
	}

	debuginfo("server %s port %s path %s", server, port, path);

	// DNS lookup of address
	struct addrinfo hints = {0}, *addr;
	hints.ai_family = AF_UNSPEC;      //Either IPv4 or IPv6
	hints.ai_socktype = SOCK_STREAM;  //TCP
	hints.ai_protocol = IPPROTO_TCP;  //TCP
	result = getaddrinfo(server, port, &hints, &addr);
	if (result) {
#ifdef _WIN32
		// Unlike Linux, on Windows gai_strerror isn't threadsafe, so use WSAGetLastError()
		const char *err = lasterror();
#else
		// Can't use lasterror: getaddrinfo doesn't set errno
		const char *err = gai_strerror(result);
#endif
		debug(errError, "getaddrinfo(%s) failed: %s", server, err);
		req->failed = true;
		return false;
	}

	// Create socket (a file descriptor under Unix)
	SOCKET sock = socket(addr->ai_family, addr->ai_socktype, addr->ai_protocol);
	if (sock == INVALID_SOCKET) {
		debug(errError, "socket(%s) error: %s", server, lasterror());
		freeaddrinfo(addr);
		req->failed = true;
		return false;
	}

	// Connect
	result = connect(sock, addr->ai_addr, addr->ai_addrlen);
	if (result == SOCKET_ERROR) {
		// Not bothering to attempt to connect to the next available address from addr
		debug(errError, "connect(%s) error: %s", server, lasterror());
		closesocket(sock);
		freeaddrinfo(addr);
		req->failed = true;
		return false;
		//sock = INVALID_SOCKET;
	}

	freeaddrinfo(addr);

	// Build the header
	const int HDRBUFSZ = 256;
	char hdrbuf[HDRBUFSZ], *hdrptr = hdrbuf, *hdrend = hdrbuf + HDRBUFSZ;
	hdrptr += snprintf(hdrptr, hdrend - hdrptr,
			    "%s %s HTTP/1.1\r\nHost: %s:%s\r\nUser-Agent: OHRRPGCE\r\n", verb, path, server, port);
	if (data) {
		hdrptr += snprintf(hdrptr, hdrend - hdrptr, "Content-Length: %d\r\n", datalen);
	}
	hdrptr += snprintf(hdrptr, hdrend - hdrptr, "\r\n");
	int hdrlen = hdrend - hdrptr;
	debuginfo(hdrbuf);

	// Send the data
	if (!send_on_socket(sock, hdrbuf, hdrlen, req, server))
		return false;
	if (data)
		if (!send_on_socket(sock, data, datalen, req, server))
			return false;

	shutdown(sock, SHUT_WR);  // Tell that we won't be sending any more (optional)

	// Recieve the response
	int recvbuf_len = 4096;
	int received = 0;
	do {
		if (!req->response_buf || recvbuf_len - received < 4096) {  //Grow buffer as needed
			recvbuf_len *= 2;
			req->response_buf = realloc(req->response_buf, recvbuf_len);
		}
		result = recv(sock, req->response_buf + received, recvbuf_len - received - 1, 0);  // Space for NUL
		if (result == SOCKET_ERROR) {
			debug(errError, "recv(%s) error: %s", server, lasterror());
			req->failed = true;
			break;
		} else {
			received += result;
		}
	} while (result > 0);
	req->response_buf[received] = '\0';
	req->response_len = received;

	debugc(errInfo, req->response_buf);
	parse_HTTP_response(req);

	closesocket(sock);
	return true;
}