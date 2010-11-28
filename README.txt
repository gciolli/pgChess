h1. pgChess

Let "chessgame" be a type representing the status of a chess game at a
certain point in time.

The goal is to implement a function

  next_move : chessgame -> chessgame

which "makes the next move".

The strategy of next_move will be to consider all the possible moves,
associate a score to each move, and select the move with the highest
score.

The score associated to a certain move will be the maximum score among
all the "foreseeable" sequences of moves that start with that move.
The database infrastructure is supposed to be helpful in dealing with
this kind of problems.

We need to implement a function

  valid_moves : chessgame -> chessmove[]

which computes a list of all the valid moves for a given game.  We
also need to implement a function

  apply_move : (chessmove,chessgame) -> chessgame

that computes the chessgame obtained by executing a given move on
a given chessgame.

The function next_move will compute all the possible sequences of
moves up to a certain "depth" D. There will be a table

	CREATE TABLE possible_move (
		d	int
	,	g	chessgame
	,	m	chessmove[]
	);

Input data:

	_g chessgame

Variables:

	_i integer

Code:

	TRUNCATE possible_move;
	INSERT INTO possible_move(d,g,m) VALUES (0,_g,ARRAY[]);
	FOR _i = 1 .. D LOOP
	INSERT INTO possible_move(d,g,m)
	SELECT	_i
	,	g
	,	(g).m || (v).m
	FROM (
		SELECT	valid_moves(g) as v
		,	g
		,	m
		FROM	possible_move	p
		WHERE	d = _i - 1
	) x;

	END LOOP;

---8<------8<------8<------8<------8<------8<------8<------8<------8<---

create a file which says:

  \o varfile1.sql
  SELECT another_move(true);
  \o
  \i varfile1.sql
  
The output of another_move(true) is:
  
  \o varfile2.sql
  SELECT another_move(false);
  \o
  \i varfile2.sql
  
and the output of another_move(false) is:

  \o varfile1.sql
  SELECT another_move(true);
  \o
  \i varfile1.sql

---8<------8<------8<------8<------8<------8<------8<------8<------8<---

TODO: find a "minimal" game to test the framework (chess is too
complicated for the base testing). That could be tic-tac-toe.

There is a "state" of the game.

Each player has to play a move selecting from a finite set of possible
moves.

To each "state" we associate a score, which is a real number. Player 1
wins if the score becomes plus infinity, player 2 wins if it becomes
minus infinity; both players try to move the score towards their own
winning point.

---8<------8<------8<------8<------8<------8<------8<------8<------8<---

h1. How to implement check and checkmate

Rule: "It is forbidden to leave your own King under attack".

That is: "Acceptable moves are only those that leave your King
     	 protected".

Then we only need a simple check to distinguish checkmate (when there
are no acceptable moves and your King is under attack) from stalemate
(when there are no acceptable moves and your King is not under
attack).

The implementation can rely on a simple function

  is_king_under_attack : gamestate -> boolean

which should be optimised for speed (maybe with a cache table, see
"Optimising storage" below).

h2. Reference implementation of is_king_under_attack(gamestate)

Input: gamestate (score real, moves gamemove[], board chess_square[])

"board" is a 8x8 array of chess_square.

1. determine whose turn is next.

   We will say "us" meaning the side that moves next, and "enemy"
   meaning the other side.

2. for each enemy square in the board:
     if it attacks our King then returns true

3. returns false

How to check if a square (x,y) attacks own king in (x0,y0)?

  FOR EACH (x,y) such that Enemy @ (x,y) LOOP
    PERFORM m.* FROM prevalid_moves(x,y) WHERE m.x2 = x0 and m.y2 = y0;
    IF FOUND RETURN true;
  END LOOP;
  RETURN false;

Note: we use "prevalid_moves" instead of "valid_moves" because to put
the King under attack using a piece X we do not require X to be able
to move. For instance:

. . . . . R K .
. k . . . . Q .
. . . . . . . R
. . . . . . . .
. . . . . . . .
. . . . . . . .
. . . . . . q .
. . . . . . . .

here the attack on k is real, although in practice Q can't move
because it has to protect K from q's attack. Hence it is checkmate,
although if Q had to capture k then q would capture K at the next
move.

Note: we have to add a "side" parameter to "prevalid_moves" since on
the same gamestate we are interested about both our moves (when we are
exploring possible moves) and their moves (when we are checking
whether our King is under attack or not).

h1. Other

h2. Optimising storage

We have 12 pieces (KQRBNPkqrbnp); hence each gamestate can be stored
in 4 * 64 = 256 bits = 32 bytes. Four additional bits are needed to
store castling information. The actual information required is 13^64,
which is held in 237 bits, hence there is plenty of space anyway.
However the more likely configurations are quite sparse, and at any
time the maximum density of pieces is 1/2; hence it might be desirable
to have some sort of compression.

Let us reason in terms of 4-bit numbers.

* 1-12: pieces
* 0,13,14,15: escape codes

We could expand 13 to (0,0), 14 to (0,0,0,0) and 15 to
(0,0,0,0,0,0,0,0).

h2. Avoiding duplicate computations

Move := datum of "(x1,y1) -> (x2,y2)" (:d_chess_square), in the
     	context of a gamestate

Prevalid move := move M allowed by the movement rules of the piece

Valid move := prevalid move M which does not leave own King under
      	      attack, endowed with the list of all the possible
      	      prevalid moves that follow M

The algorithm to compute the list of valid moves is:

  * IF G.next_moves THEN
       G.next_moves := prevalid moves(G);
    END IF;
  * for each prevalid move M, compute the list of possible prevalid
    moves P_1,...,P_n that can follow M
  * if there is a P_i that attacks the King, then M is not a valid move;
    otherwise:
    
      M.mine := ROW(x1,y1,x2,y2)::d_chess_square
      M.theirs := ARRAY[P_1,...,P_n]
      M.dscore := dscore_of_gamemove(current_gamestate,M.mine)
      RETURN NEXT M;

This algorithm will produce a list of valid moves.

