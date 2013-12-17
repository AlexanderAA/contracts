structure Contract :> CONTRACT_UNSAFE = struct
open ContractBase Currency
type 'a exp = exp0
type boolE = bool exp
type 'a num = unit
type intE = int num exp
type realE = real num exp

local
  type hash = IntInf.int
  val Alpha = IntInf.fromInt 65599
  val Beta = IntInf.fromInt 19
  fun H (p,a) = IntInf.*(IntInf.fromInt p,
                         IntInf.+(a,IntInf.fromInt 1))
  fun hashAdd (w:IntInf.int, acc) = let open IntInf in w+acc*Beta end
  fun Hs (s,a:hash) =
	let val sz = size s
	    fun loop (n,a) = 
		if n >= sz then a
		else loop (n+1, 
			   hashAdd 
			       (IntInf.fromInt(Char.ord(String.sub(s,n))), a))
	in loop (0,a)
	end
in
fun hashExp (e,a) =
    case e of
        I i => H(2,H(i,a))
      | R r => H(3,Hs(Real.toString r, a))
      | B true => H(5,a)
      | B false => H(7,a)
      | Var v => H(11, Hs(v,a))
      | BinOp(s,e1,e2) => Hs(s,hashExp(e1,hashExp(e2,a)))
      | UnOp(s,e) => Hs(s,hashExp(e,a))
      | Obs(s,i) => H(13,Hs(s,H(i,a)))
fun hashContr (c,a) = 
    case c of
        Zero => H(2,a)
      | Both(c1,c2) => let open IntInf in hashContr(c1,IntInf.fromInt 0) + hashContr(c2,IntInf.fromInt 0) + a end
      | TransfOne(cur,p1,p2) => Hs(ppCur cur,Hs(p1,Hs(p2,H(3,a))))
      | If(e,c1,c2) => hashContr(c1,hashContr(c2,hashExp(e,H(5,a))))
      | Scale(e,c) => hashExp(e,hashContr(c,H(7,a)))
      | Transl(i,c) => H(i, hashContr(c,H(11,a)))
      | CheckWithin(e1,i,c1,c2) => hashContr(c1,hashContr(c2,hashExp(e1,H(i,H(13,a)))))
end

fun eqExp (e1,e2) =
    IntInf.compare(hashExp(e1,IntInf.fromInt 0),
                   hashExp(e2,IntInf.fromInt 0)) = EQUAL

fun eqContr (c1,c2) =
    IntInf.compare(hashContr(c1,IntInf.fromInt 0),
                   hashContr(c2,IntInf.fromInt 0)) = EQUAL

infix !+! !-! !*! !<! !=! !|!
fun x !+! y = BinOp("+",x,y)
fun x !-! y = BinOp("-",x,y)
fun x !*! y = BinOp("*",x,y)
fun x !<! y = BinOp("<",x,y)
fun x !=! y = BinOp("=",x,y)
fun x !|! y = BinOp("|",x,y)
fun not x = UnOp("not",x)
fun max (x,y) = BinOp("max",x,y)
fun min (x,y) = BinOp("min",x,y)

val obs : (string*int) -> 'a exp = Obs

fun binopII opr i1 i2 =
    case opr of
        "+" => I (i1+i2)
      | "-" => I (i1-i2) 
      | "*" => I (i1*i2) 
      | "<" => B (i1<i2) 
      | "=" => B (i1=i2)
      | "max" => I(if i1 >= i2 then i1 else i2)
      | "min" => I(if i1 <= i2 then i1 else i2)
      | _ => raise Fail ("binopII: operator not supported: " ^ opr)

fun binopRR opr r1 r2 =
    case opr of
        "+" => R (r1+r2)
      | "-" => R (r1-r2) 
      | "*" => R (r1*r2) 
      | "<" => B (r1<r2) 
      | "=" => B (Real.compare(r1,r2) = EQUAL) 
      | "max" => R(if r1 >= r2 then r1 else r2)
      | "min" => R(if r1 <= r2 then r1 else r2)
      | _ => raise Fail ("binopRR: operator not supported: " ^ opr)

fun binopBB opr b1 b2 =
    case opr of
        "=" => B (b1=b2)
      | "|" => B (b1 orelse b2)
      | _ => raise Fail ("binopBB: operator not supported: " ^ opr)

fun binop opr e1 e2 =
    let fun mk() = BinOp(opr,e1,e2)
    in case opr of
           "-" => if eqExp(e1,e2) then I 0 else mk()
         | "min" => if eqExp(e1,e2) then e1 else mk()
         | "max" => if eqExp(e1,e2) then e1 else mk()
         | "<" => if eqExp(e1,e2) then B false else mk()
         | "=" => if eqExp(e1,e2) then B true else mk()
         | "|" => if eqExp(e1,e2) then e1 else mk()
         | _ => mk()
    end

type date = Date.date

type env = string*date*int -> real option   (* int is a date offset *)

val emptyEnv : env = fn _ => NONE

fun eqDate d1 d2 =
    Date.compare (d1,d2) = EQUAL
                                                                                      
fun addFixing ((s,d,r),e:env) : env = 
    fn k => 
       let val off = #3 k
       in if s = #1 k andalso off >= 0 andalso eqDate d (DateUtil.addDays off (#2 k)) then SOME r
          else if s = #1 k andalso off < 0 andalso eqDate (DateUtil.addDays (~off) d) (#2 k) then SOME r
          else e k
       end

fun eval (E:env,d:date) e =
    case e of
        Var s => e
      | I _ => e
      | R _ => e
      | B _ => e
      | Obs (s,off) =>
        (case E (s,d,off) of
             SOME r => R r
           | NONE => e)
      | BinOp(opr,e1,e2) => 
        (case (eval (E,d) e1, eval (E,d) e2) of
               (I i1, I i2) => binopII opr i1 i2
             | (R r1, R r2) => binopRR opr r1 r2
             | (B b1, B b2) => binopBB opr b1 b2
             | (e1,e2) => binop opr e1 e2)
      | UnOp("not", e1) => 
        (case eval (E,d) e1 of
             B b => B(Bool.not b)
           | e1 => UnOp("not",e1))
      | UnOp(opr,_) => raise Fail ("eval.UnOp: unsupported operator: " ^ opr)

fun evalR E e = 
    case eval E e of R r => r
                   | _ => raise Fail "evalR: expecting real"
fun evalI E e =
    case eval E e of I i => i
                   | _ => raise Fail "evalI: expecting int"
fun evalB E e =
    case eval E e of B b => b
                   | _ => raise Fail "evalB: expecting bool"
         
fun ppTime t = 
    let val months = t div 30
        val years = t div 360
        val months = months mod 12
        val days = t mod 30
        val s = if days = 0 then "" else Int.toString days ^ "d"
        val s = if months = 0 then s else Int.toString months ^ "m" ^ s
        val s = if years = 0 then s else Int.toString years ^ "y" ^ s
    in if s = "" then "0d" else s
    end
                       
fun ppExp0 ppTime e = 
    let fun par s = "(" ^ s ^ ")"
        fun notfixed opr = opr = "max" orelse opr = "min"
    in case e of 
           Var s => "Var" ^ par s
         | I i => ppTime i
         | R r => Real.toString r
         | B b => Bool.toString b
         | Obs (s,off) => "Obs" ^ par (s ^ "@" ^ ppTime off)
         | BinOp(opr,e1,e2) => 
           if notfixed opr then opr ^ par (ppExp e1 ^ "," ^ ppExp e2)
           else par(ppExp e1 ^ opr ^ ppExp e2)
         | UnOp(opr, e1) => opr ^ par (ppExp e1)
    end
and ppExp e = ppExp0 Int.toString e
val ppTimeExp = ppExp0 ppTime

fun certainExp e =
    case e of
        Var _ => false
      | I _ => true
      | R _ => true
      | B _ => true
      | Obs _ => false
      | BinOp(_,e1,e2) => certainExp e1 andalso certainExp e2
      | UnOp(_,e1) => certainExp e1
                              
fun simplifyExp P e =
    eval P e

fun translExp (e, 0) = e
  | translExp (e, d) =
    case e of
        Obs (s,t) => obs (s,t+d)
      | BinOp(s,e1,e2) => BinOp (s, translExp (e1, d), translExp (e2, d))
      | UnOp(s,e1) => UnOp (s, translExp (e1, d))
      | other => e (* rest unmodified *)

fun ppContr c =
    let fun par s = "(" ^ s ^ ")"
    in case c of
           TransfOne(c,p1,p2) => "TransfOne" ^ par (ppCur c ^ "," ^ p1 ^ "," ^ p2)
         | Scale (e,c) => "Scale" ^ par (ppExp e ^ "," ^ ppContr c)
         | Transl(i,c) => "Transl" ^ par (ppTimeExp (I i) ^ "," ^ ppContr c)
         | Zero => "zero"
         | Both (c1,c2) => "Both" ^ par (ppContrs[c1,c2])
         | If(e,c1,c2) => "If" ^ par (ppExp e ^ ", " ^ ppContr c1 ^ ", " ^ ppContr c2)
         | CheckWithin (e, i, c1, c2) => 
           "CheckWithin" ^ par (ppExp e ^ ", " ^ ppTimeExp (I i) ^ ", "  ^ ppContr c1 ^ ", " ^ ppContr c2)
    end
and ppContrs [] = ""
  | ppContrs [c] = ppContr c
  | ppContrs (c::cs) = ppContr c ^ ", " ^ ppContrs cs

val zero = Zero
val transfOne = TransfOne
fun transl (0,c) = c
  | transl (i,c) =
    if i < 0 then raise Fail "transl: negative time"
    else case c of             
             Zero => zero
           | Transl(i',c) => transl(i+i',c)
           | _ => Transl(i,c) 

fun iff (B true,  c1,c2) = c1
  | iff (B false, c1,c2) = c2
  | iff (b,c1,c2) = if eqContr(c1,c2) then c1
                    else If(b,c1,c2)

fun checkWithin (b,0,c1,c2) = iff (b,c1,c2)
  | checkWithin (b,i,c1,c2) = if i > 0 then CheckWithin (b,i,c1,c2)
                              else raise Fail "checkWithin: negative duration"

fun both (Zero,c2) = c2
  | both (c1,Zero) = c1
  | both (c1,c2) = Both(c1,c2)

fun all [] = Zero
  | all [c] = c
  | all (c::cs) = both(c,all cs)

fun scale (_,Zero) = zero
  | scale (r,Scale(r',c)) = scale(r !*! r', c)
  | scale (r,t) = if eqExp(R 0.0, r) then zero
                  else if eqExp(R 1.0, r) then t
                  else Scale(r,t)

(* Shorthand notation *)
fun flow(d,v,c,from,to) = scale(v,transl(d,transfOne(c,from,to)))

val rec dual = 
 fn Zero => zero
  | TransfOne(c,p1,p2) => transfOne(c,p2,p1)
  | Scale (e,c) => scale(e,dual c)
  | Transl(i,c) => transl(i,dual c)
  | Both(c1,c2) => both (dual c1, dual c2)
  | If(e,c1,c2) => iff(e,dual c1, dual c2)
  | CheckWithin (e, i, c1, c2) => checkWithin (e, i, dual c1, dual c2)

(* Contract Management *)
fun simplify P t =
    case t of
        Zero => zero
      | Both(c1,c2) => both(simplify P c1, simplify P c2)
      | Scale(obs,Both(c1,c2)) => simplify P (both(scale(obs,c1),scale(obs,c2)))
      | Scale(r,t) => scale(simplifyExp P r,simplify P t)
      | Transl(i,t') =>
        let val (E,d) = P
            val P' = (E, DateUtil.addDays i d)
            val t' = simplify P' t'
        in transl(i,t')
        end
      | TransfOne _ => t
      | If (e, c1, c2) => 
        let val e = simplifyExp P e
            val c1 = simplify P c1
            val c2 = simplify P c2
        in iff(e,c1,c2)
        end
      | CheckWithin (e, i, c1, c2) => checkWithin (simplifyExp P e, i, c1, simplify P c2)

type cashflow   = date * cur * party * party * bool * realE
fun ppCashflow w (d,cur,p1,p2,certain,e) =
    let fun sq s = "[" ^ s ^ "]"
        fun pad w s =
            s ^ CharVector.tabulate (w - size s, fn _ => #" ")
        fun ppCertain true = "Certain"
          | ppCertain false = "Uncertain"
    in String.concatWith " "
       [Date.fmt "%Y-%m-%d" d,
        ppCertain certain,
        pad w (sq(p1 ^ "->" ^ p2)),
        ppCur cur,
        ppExp (simplifyExp (emptyEnv,d) e)]
    end

fun ppCashflows [] = "no cashflows"
  | ppCashflows l =  
    let val szs = List.map (fn (_,_,p1,p2,_,_) => size p1 + size p2 + 4) l
        val sz = List.foldl(fn (i,a) => if i > a then i else a) 0 szs
    in String.concatWith "\n" (List.map (ppCashflow sz) l)
    end

fun cashflows d c : cashflow list =
    let fun cf (d,c,s,certain) =
            case c of
                Zero => nil
              | TransfOne(c,p1,p2) => [(d,c,p1,p2,certain,s)]
              | Both(c1,c2) => cf(d,c1,s,certain) @ cf(d,c2,s,certain)
              | Scale(s',c) => cf(d,c,s !*! s',certain)
              | Transl(i,c2) =>
                let val d' = DateUtil.addDays i d
(*
                    val () = print ("d=" ^ Date.toString d ^ "\n")
                    val () = print ("i=" ^ Int.toString i ^ "\n")
                    val () = print ("d'=" ^ Date.toString d' ^ "\n")
*)
                in cf(d',c2,s,certain)
                end
              | If(b,c1,c2) => cf(d,c1,s,false) @ cf(d,c2,s,false)
              | CheckWithin(e,i,c1,c2) =>
                if i <= 0 then nil
                else cf(d,c1,s,false) @
                     cf(d,c2,s,false) @
                     cf(DateUtil.addDays 1 d,
                        checkWithin(translExp(e,i),i-1,c1,c2),s,certain)
        val flows = cf(d,c,R 1.0,true)
    in ListSort.sort (fn ((d1,_,_,_,_,_),(d2,_,_,_,_,_)) => Date.compare (d1,d2)) flows
    end

end