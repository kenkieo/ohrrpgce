'OHRRPGCE - Custom+Game common battle system code
'(C) Copyright 1997-2005 James Paige and Hamster Republic Productions
'Please read LICENSE.txt for GNU GPL details and disclaimer of liability

#include "const.bi"
#include "util.bi"
#include "config.bi"
#include "common.bi"
#include "loading.bi"

'This is similar to fuzzythreshold. It interpolates between these values:
' 0.12  0.24  1.00  2.00 ...  x
'  0     1     0     1      x - 1 
FUNCTION fuzzy_strong_amount (byval value as double) as double
 IF value <= 0.12 THEN
  RETURN 0.0
 ELSEIF value <= 0.24 THEN
  RETURN (value - 0.12) / 0.12
 ELSEIF value <= 1.0 THEN
  RETURN (1.0 - value) / 0.76
 ELSE
  RETURN value - 1.0
 END IF
END FUNCTION

'Merge elemental resist values from one item into the hero's cumulative resists,
'by simulating the old way of just ORing together all the bits. Uses linear
'interpolation to generalise the required results on inputs of combinations of
'0, 12, 24, 100, 200% to arbitrary values. The results can be pretty unexpected.
FUNCTION awful_compatible_equip_elemental_merging (values() as single) as single
 DIM sign as integer = 1
 'fuzzy logic! 0 <= weak_bit <= 1,  0 <= strong_amount
 'strong_amount is a fuzzy truth value for "doubling", generalised to more than 200%
 DIM as double weak_bit = -1.0, strong_amount = -1.0
 DIM as double immunemult = 1.0
 FOR i as integer = 0 TO UBOUND(values)
  IF isfinite(values(i)) = NO THEN CONTINUE FOR
  IF values(i) < 0 THEN sign = -1
  DIM absval as double = ABS(values(i))

  weak_bit = large(weak_bit, fuzzythreshold(absval, 1.0, 0.24))
  strong_amount = large(strong_amount, fuzzy_strong_amount(absval)) 
  'These fuzzythresholds simulate an 'immune' bit, restoring just a shred of sanity to the results
  immunemult *= fuzzythreshold(absval, 0, 0.12)
 NEXT

 DIM as double weakmult, strongmult
 weakmult = weak_bit * 0.12 + (1.0 - weak_bit) * 1.0
 strongmult = strong_amount * 2.0 + (1.0 - strong_amount) * 1.0
 RETURN sign * weakmult * strongmult * immunemult
END FUNCTION

'Merge elemental resist values from one item into the hero's cumulative resists,
'by multiplication (a sane version of the old way)
FUNCTION multiplicative_equip_elemental_merging (values() as single) as single
 DIM sign as integer = 1
 DIM ret as double = 1.0
 FOR i as integer = 0 TO UBOUND(values)
  IF isfinite(values(i)) = NO THEN CONTINUE FOR
  IF values(i) < 0 THEN sign = -1
  ret *= ABS(values(i))
 NEXT
 RETURN sign * ret
END FUNCTION

'Merge elemental resist values from one item into the hero's cumulative resists,
'by adding together the differences from 1.0
FUNCTION additive_equip_elemental_merging (values() as single) as single
 DIM ret as double = 1.0
 FOR i as integer = 0 TO UBOUND(values)
  IF isfinite(values(i)) = NO THEN CONTINUE FOR
  ret += values(i) - 1.0
 NEXT
 RETURN ret
END FUNCTION

FUNCTION equip_elemental_merge(values() as single, byval formula as integer) as single
 SELECT CASE formula
  CASE 0:
   RETURN awful_compatible_equip_elemental_merging(values())
  CASE 1:
   RETURN multiplicative_equip_elemental_merging(values())
  CASE 2:
   RETURN additive_equip_elemental_merging(values())
 END SELECT
END FUNCTION

'Adjust the MP cost of an attack according to focus stat
FUNCTION focuscost (cost as integer, focus as integer) as integer
 IF focus > 0 THEN
  RETURN cost - INT(cost / (100 / focus))
 ELSE
  RETURN cost
 END IF
END FUNCTION

'magic_list_type: 0 for normal/random spell lists, 1 for level mp
'lmp_level: -1 if no cost, otherwise 0-based level-MP level
FUNCTION attack_cost_info(byref atk as AttackData, byval focus as integer=0, byval cur_mp as integer=0, byval max_mp as integer=0, byval magic_list_type as integer=0, byval lmp_level as integer=-1, byval cur_lmp as integer=0) as string

 DIM cost_s as string
 DIM vec as string vector
 v_new vec

 FOR i as integer = 0 TO UBOUND(atk.item)
  IF atk.item(i).id > 0 ANDALSO atk.item(i).number <> 0 THEN
   DIM item_name as string = readitemname(atk.item(i).id - 1)
   cost_s = item_name & CHR(1) & ABS(atk.item(i).number)
   IF atk.item(i).number < 0 THEN cost_s = "+" & cost_s
   v_append vec, cost_s
  END IF
 NEXT i

 IF atk.money_cost <> 0 THEN
  cost_s = ABS(atk.money_cost) & "$"  
  IF atk.money_cost < 0 THEN cost_s = "+" & cost_s
  v_append vec, cost_s
 END IF

 IF atk.hp_cost <> 0 THEN
  cost_s = ABS(atk.hp_cost) & " " & statnames(statHP)
  IF atk.hp_cost < 0 THEN cost_s = "+" & cost_s
  v_append vec, cost_s
 END IF
 
 IF atk.mp_cost <> 0 THEN
  DIM mp_cost as integer = focuscost(atk.mp_cost, focus)
  cost_s = ABS(mp_cost) & " " & statnames(statMP) & " " & cur_mp & "/" & max_mp  
  IF mp_cost < 0 THEN cost_s = "+" & cost_s
  v_append vec, cost_s
 END IF

 IF magic_list_type = 1 ANDALSO lmp_level > -1 THEN
  'Uses level-based MP
  cost_s = readglobalstring(160, "Level MP", 20) & " " & (lmp_level + 1) & ": " & cur_lmp
  v_append vec, cost_s
 END IF
 
 DIM result as string 
 FOR i as integer = 0 to v_len(vec) - 1
  IF LEN(result) > 0 THEN result &= " "
  result &= vec[i]
 NEXT i
 v_free vec
 RETURN result
END FUNCTION

FUNCTION describe_formation(formdata as Formation) as string
 'Return a string that describes a battle formation
 DIM max as integer = UBOUND(formdata.slots)
 DIM counts(max) as XYPair 'x=id y=count
 FOR i as integer = 0 TO max
  counts(i).x = -1
 NEXT i
 
 DIM id as integer
 FOR i as integer = 0 TO max
  id = formdata.slots(i).id
  IF id >= 0 THEN
   FOR j as integer = 0 TO max
    IF counts(j).x = id THEN
     counts(j).y += 1
     EXIT FOR
    END IF
    IF counts(j).x = -1 THEN
     counts(j).x = id
     counts(j).y = 1
     EXIT FOR
    END IF
   NEXT j
  END IF
 NEXT i

 DIM nam as string 
 DIM num as integer
 DIM result as string = ""
 FOR i as integer = 0 TO UBOUND(counts)
  id = counts(i).x
  num = counts(i).y
  IF id >= 0 THEN
   nam = exclude(readenemyname(id), " ")
   IF LEN(nam) = 0 THEN nam = "Enemy" & id
   IF result <> "" THEN result &= " "
   result &= nam
   IF num <> 1 THEN result &= "*" & num 
  END IF
 NEXT i
 
 RETURN result
END FUNCTION

FUNCTION describe_formation_by_id(byval form_id as integer) as string
 DIM form as Formation
 LoadFormation form, game & ".for", form_id
 RETURN describe_formation(form)
END FUNCTION
