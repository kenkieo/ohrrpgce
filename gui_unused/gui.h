//gui.h
//by Jay Tennant 2/19/12
//port of GUI manager to OHR engine

#pragma once

extern "C" {

//list of GUI_MESSAGES
enum GUI_MESSAGES
{
	//GUI_HITTEST,				//param1 is depth value, param2 is int[2] with x,y mouse coordinates in absolute position, returns it's depth if it is >= param1 and x,y coordinates transformed to the object still pass
	GUI_CREATE,					//param2 is creationParams, returns 0 on success, or a value for error
	GUI_DESTROY,				//no params
	GUI_MOVE,					//param2 is int[2] with x,y coordinates of location to move to, relative to parent
	//GUI_MOVE_FROM_PARENT,		//param2 is int[2] with x,y coordinates of parent's absolute upper-left corner
	GUI_SIZE,					//param2 is unsigned int[2] with x,y dimensions of new object size

	GUI_MOUSE_OVER,				//param1 is true if mouse is over, false if it is not, param2 is const Mouse struct ptr
	GUI_MOUSE_MOVE,				//param1 is amount moved, loword being signed x coord, hiword being signed y coord, param2 is const Mouse struct ptr
	//GUI_MOUSE_HOVER,			//param1 is duration, param2 is const Mouse struct ptr
	GUI_MOUSE_LBUTTON_DOWN,		//param1 is button code (GUIC_BUTTON_*), param2 is const Mouse struct ptr
	GUI_MOUSE_LBUTTON_UP,		//param1 is button code (GUIC_BUTTON_*), param2 is const Mouse struct ptr
	GUI_MOUSE_LCLICK,			//param2 is const Mouse struct ptr
	GUI_MOUSE_RBUTTON_DOWN,		//param1 is button code (GUIC_BUTTON_*), param2 is const Mouse struct ptr
	GUI_MOUSE_RBUTTON_UP,		//param1 is button code (GUIC_BUTTON_*), param2 is const Mouse struct ptr
	GUI_MOUSE_RCLICK,			//param2 is const Mouse struct ptr
	GUI_MOUSE_MBUTTON_DOWN,		//param1 is button code (GUIC_BUTTON_*), param2 is const Mouse struct ptr
	GUI_MOUSE_MBUTTON_UP,		//param1 is button code (GUIC_BUTTON_*), param2 is const Mouse struct ptr
	GUI_MOUSE_MCLICK,			//param2 is const Mouse struct ptr
	GUI_KEY_DOWN,				//param1 is the combination of key codes (GUIC_KEY_*) in the loword, InputScancode in the hiword (hint: use GuiKey), param2 is the InputKey code
	GUI_KEY_UP,					//param1 is the combination of key codes (GUIC_KEY_*) in the loword, InputScancode in the hiword (hint: use GuiKey), param2 is the InputKey code
	GUI_KEY_TOUCH,				//param1 is the combination of key codes (GUIC_KEY_*) in the loword, InputScancode in the hiword (hint: use GuiKey), param2 is the InputKey code
	GUI_CHAR,					//param1 is the char

	//GUI_FOCUS,					//param1 is the focus code
	//GUI_IS_MOVABLE_BY_MOUSE,	//returns 1 for true, 0 for false; default value is true
	//GUI_GET_ABS_POSITION,		//param2 is GuiRect* to receive the absolute position of the object
	//GUI_GET_REL_POSITION,		//param2 is GuiRect* to receive the position of the object relative to the parent
	//GUI_GET_SIZE,				//param2 is uint2 ptr to receive the dimensions of the object
	//GUI_GET_TEXT,				//param1 specifies how large the buffer of param2 is, param2 is a char buffer that receives the text, returns the number of characters copied
	//GUI_SET_TEXT,				//param1 is how many characters to copy or -1 for the whole string, param2 is a char buffer to be copied from (if param1 is -1, the char buffer must be null terminated)
	//GUI_GET_ZORDER,				//returns the z-order or z-order code
	//GUI_SET_ZORDER,				//param1 is the z-order or z-order code; child objects should be updated, too
	//GUI_GET_TREEDEPTH,			//returns the deepest child's z-order
	//GUI_GET_CHILDCOUNT,			//returns the number of children
	//GUI_GET_CHILD,				//param1 is the index into the nth child, returns the ID of the child
	//GUI_GET_PARENT,				//returns the parent ID
	//GUI_IS_DESCENDANT,			//param1 is the ID of the possible anscestor
	//GUI_IS_ANSCESTOR,			//param1 is the ID of the possible descendant
	GUI_COMMAND,				//param1 is the notification code (dependent on control type), param2 is the control ID that sent this message
};

enum GUI_CODES
{
	GUIC_INVALID = -1,
	GUIC_BUTTON_UP = 0,
	GUIC_BUTTON_DOWN = 1,
	GUIC_KEY_UP = 0,
	GUIC_KEY_DOWN = 1,
	GUIC_KEY_PREVIOUS_STATE = 0x1,
	GUIC_KEY_SHIFT = 0x2,
	GUIC_KEY_CTRL = 0x4,
	GUIC_KEY_ALT = 0x8,
	//GUIC_KEY_CAPS_LOCK = 0x10,
	//GUIC_KEY_NUM_LOCK = 0x20,
	//GUIC_KEY_SCROLL_LOCK = 0x40,
	GUIC_FOCUS_LOSE = 0,
	GUIC_FOCUS_GAIN = 1,
	//GUIC_ZORDER_TOPMOST = -1,
	//GUIC_ZORDER_BOTTOMMOST = -2,
	//GUIC_ZORDER_TOP = -3,
	//GUIC_ZORDER_BOTTOM = -4,
};



//starts the GUI system
void guiStart();

//shuts down the GUI system
void guiStop();

//GUIPROC definition
typedef int __cdecl (*GUIPROC)(unsigned int id, unsigned int msg, unsigned int param1, void* param2);

struct GuiClass {
	GUIPROC guiProcedure; //the procedure called for each message sent
	int numExtraBytesPerClass; //the number of extra bytes to allocate for the class; accessed via guiGetClassExtraBytes() or guiGetClassExtraBytesByName()
	int numExtraBytesPerObject; //the number of extra bytes to allocate for the object; accessed via guiGetObjectExtraBytes()
	char szClassName[32]; //unique name for the class
};

//registers a GUICLASS to the manager;
//returns 0 on failure, non-zero on success
int guiRegisterClass( GuiClass* p );

//unregisters a previously registered GUICLASS, freeing allocated memory for the class
void guiUnregisterClass( const char* szClass );

struct GuiRect {
	int left, top, right, bottom;
};

struct GuiObjectState {
	unsigned int id; //ID of the object
	GuiRect position; //the position rectangle of the object in screen coordinates
	GuiRect clippingRect; //the clipping rectangle of the object in screen coordinates
	GuiRect range; //the range of the object in x and y; ie. control knob from 0 to 360, scroll bar from 0 to 50, number of columns and rows in a table, or a highlighted selection
	int rangePositionX; //the position of the indicator within the x range; ie. slider's pointer position, caret column position
	int rangePositionY; //the position of the indicator within the y range; ie. scroll bar's position, caret row position
	int cursor; //what cursor should appear over this control; 0 means "don't care"
	const char* szText; //constant pointer to the text buffer for the control

	//following could be combined to a bitwise OR'ed DWORD
	int isFocused;
	int isSelected;
	int isEnabled;
	int isChecked;
	int isHighlighted;
	int isClipping;
	int isMouseOver;
	int isMouseLButtonDown;
	int isMouseRButtonDown;
	int isMouseMButtonDown;
};

//creates a GUI object, returning the ID of the created object;
//returns the ID of the new GUI object
//szClass is the name of the class, ie. "BUTTON";
//szText is the initial text sent to the object;
//dwFlags is the creation flags, specifying style, etc.--generally specific to a control;
//x and y are the upper-left corner coordinates;
//width and height are the dimensions of the client area;
//commandID is the code sent during a notification, ie. a BUTTON sends BN_CLICKED with the commandID value;
//parentID is the ID of the parent; if 0, this object is "unparented";
//pExtra is extra data that can be sent, specific to a control;
unsigned int guiCreate( const char* szClass, const char* szText, unsigned int dwFlags, int x, int y, int width, int height, int commandID, unsigned int parentID, void* pExtra );

//destroys a GUI object, freeing the extra bytes associated with that object
void guiDestroy( unsigned int id );

//returns a pointer to the extra data allocated for the class
void* guiGetClassExtraBytes( unsigned int id );
//returns a pointer to the extra data allocated for the class
void* guiGetClassExtraBytesByName( const char* szClass );

//returns a pointer to the extra data allocated for the object
void* guiGetObjectExtraBytes( unsigned int id );

//gets the GuiObjectState of a GUI object
void guiGetObjectState( unsigned int id, GuiObjectState* pOut );

//gets the child ID by it's index in the tree node
unsigned int guiGetChildByIndex( unsigned int parentID, int index );

//gets the number of children objects for the specified tree node
int guiGetChildCount( unsigned int parentID );

//sends a GUI_* message to be evaluated immediately on a specific GUI object
int guiSendMessage( unsigned int id, unsigned int msg, unsigned int param1, void* param2 );

//posts a GUI_* message to the message queue for a specific GUI object, evaluated when guiPumpMessages() is called;
//WARNING: do not release any allocated memory of param2 until after guiPumpMessages() has been called
void guiPostMessage( unsigned int id, unsigned int msg, unsigned int param1, void* param2 );

//processes all messages in the message queue;
//any memory allocated in a guiPostMessage() call can safely be released after calling this
void guiPumpMessages();

struct GuiMouse {
	int x, y, wheel;
	int leftButton, rightButton, middleButton;
};

struct GuiKeyboard {
	int key[128];
};

//synthesizes input messages from the static mouse and keyboard state;
//this automatically calls guiInputMessage() with each input message
void guiSynthesizeInputMessage( GuiMouse& mouse, GuiKeyboard& kb );

//adds a GUI_* message to the GUI manager's message processor;
//this is processed into GUI_* messages to the appropriate controls;
//memory allocated for param2 does not need to persist beyond this call
void guiInputMessage( unsigned int msg, unsigned int param1, void* param2 );

};