#include "postgres.h"
#include "fmgr.h"
#include "funcapi.h"
#include "utils/array.h"
#include "utils/builtins.h"

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

/* htup.h was reorganized for 9.3, so now we need this header */
#if PG_VERSION_NUM >= 90300
#include "access/htup_details.h"
#endif

/*
 * Memory context for formal_moves
 */

/* 
 * a move (x1,x2) -> (y1,y2) is represented by four 3-bit integers
 * x1,x2,y1,y2 which are encoded as a single 12-bit integer. 
 * 
 * Castling can be encoded with this scheme, by noting the movement of
 * the King.
 *
 * Two additional bits are reserved to encode the choice in case of
 * pawn promotion: 00 = queen, 01 = bishop, 10 = knight, 11 = rook.
 */

#define ChessMoveX1(x) ((x)%8)
#define ChessMoveY1(x) (((x)/8)%8)
#define ChessMoveX2(x) (((x)/64)%8)
#define ChessMoveY2(x) (((x)/512)%8)
#define ChessMoveTarget(x) (((x)/64)%64)
#define ChessMoveID(x) ((x)%64)
#define ChessMoveNextTarget(x) (((x)/64+1)*64)
#define ChessMovePPC(x) (((x)/4096)%4)
#define ChessMovePPCToChar(x) ((x) == 0 ? 'q' : ((x) == 1 ? 'b' : ((x) == 2 ? 'n' : 'r')))
#define ChessMove(x1,y1,x2,y2,ppc) (x1+(y1)*8+(x2)*64+(y2)*512+(ppc)*4096)
#define ChessValidXY(x,y) (((x)<=7)&&((x)>=0)&&((y)<=7)&&((y)>=0))
#define ChessIteratorFromTgId(tg,id) ((tg)*64+id)

#define ChessVoidMove 0
#define ChessFirstMove 1
#define ChessEndOfMoves 16384
#define ChessIteratorEnd 4096
#define ChessMoveIDMax 29

/*
 * The following coefficients control the importance of available
 * moves and attacked pieces in evaluating a position.
 */

#define ChessCoeffScoreMoves 0.1
#define ChessCoeffScoreAttacked 0.1

typedef struct
{
	/* the board */
	char b[8][8];

	/* castling information */
	char c[4];

	char last_piece_captured;

	int move_iterator;
	int candidate_move;
	int found_moves;

	int previous_moves_n;
	int *previous_moves;

	int halfmove_counter;

	/* Forsyth-Edwards Notation */
	char fen[90];
	/* 
	 * The maximum size of 89 character is computed from the maximum
	 * possible sizes for each field: 71 1 4 2 2 4. We are assuming
	 * that no game will ever reach 10000 moves, which seems quite a
	 * safe assumption; in any case, we put a safety check in the
	 * function that fills the FEN entry, to avoid segfaults.
	 */
	
} chess_game_status;

/*
 * Prototypes of auxiliary functions
 */

char aux_chess_side(char);
int aux_init_chess_game_status(chess_game_status *);
void aux_destroy_chess_game_status(chess_game_status *);
void aux_chess_apply_candidate_move(chess_game_status *);
chess_game_status * aux_clone_chess_game_status(const chess_game_status *);
int aux_read_game(chess_game_status *, Datum);
int aux_read_move(Datum);
int aux_chess_formal_move_rewind(chess_game_status *);
int aux_chess_formal_move_next(chess_game_status *);
int aux_chess_is_king_safe(const chess_game_status *);
int aux_chess_piece_value(char);
int aux_chess_score_available_pieces(chess_game_status *);
int aux_chess_score_available_moves(chess_game_status *);
int aux_chess_score_attacked_pieces(chess_game_status *);
double aux_chess_score(chess_game_status *);
void aux_chess_update_fen(chess_game_status *);

/*
 * Prototypes of PostgreSQL functions
 */

Datum chess_valid_moves(PG_FUNCTION_ARGS);
Datum chess_is_king_safe(PG_FUNCTION_ARGS);
Datum chess_is_game_ended(PG_FUNCTION_ARGS);
Datum chess_game_to_fen(PG_FUNCTION_ARGS);
Datum chess_game_score(PG_FUNCTION_ARGS);

/*
 * Functions
 */

#define aux_chess_side(X)							\
	(X == ' ' ? ' ' :								\
	 (X == 'K' ? 'w' :								\
	  (X == 'Q' ? 'w' :								\
	   (X == 'R' ? 'w' :							\
		(X == 'B' ? 'w' :							\
		 (X == 'N' ? 'w' :							\
		  (X == 'P' ? 'w' :							\
		   (X == 'k' ? 'b' :						\
			(X == 'q' ? 'b' :						\
			 (X == 'r' ? 'b' :						\
			  (X == 'b' ? 'b' :						\
			   (X == 'n' ? 'b' :					\
				(X == 'p' ? 'b' : '?')))))))))))))

int
aux_init_chess_game_status(chess_game_status *s)
{
	s->candidate_move = ChessVoidMove;
	return 0;
};

void
aux_destroy_chess_game_status(chess_game_status *s)
{
	if (s->previous_moves != NULL)
		pfree(s->previous_moves);
	pfree(s);
}

void
aux_chess_apply_candidate_move(chess_game_status *s)
{
	int x1=0, x2=0, y1=0, y2=0;
	char p1='-', p2='-';

	if (s->candidate_move != ChessVoidMove)
		{
			x1 = ChessMoveX1(s->candidate_move);
			y1 = ChessMoveY1(s->candidate_move);
			x2 = ChessMoveX2(s->candidate_move);
			y2 = ChessMoveY2(s->candidate_move);
			p1 = s->b[x1][y1];
			p2 = s->b[x2][y2];
			if (p2 != ' ')
				s->last_piece_captured = p2;
			s->b[x2][y2] = p1;
			s->b[x1][y1] = ' ';
		}
	s->previous_moves_n++;
	if (s->previous_moves == NULL)
		s->previous_moves = (int *) palloc(sizeof(int) * s->previous_moves_n);
	else
		s->previous_moves = (int *) repalloc(s->previous_moves, sizeof(int) * s->previous_moves_n);
	s->previous_moves[s->previous_moves_n - 1] = s->candidate_move;
	s->candidate_move = ChessVoidMove;

	/* 
	 * If the King moves by > 1 squares, then he is castling, and the
	 * Rook must be moved too.
	 */

	if (p1 == 'K' && x1 == 4 && x2 == 6)
		{
			s->b[5][0] = 'R';
			s->b[7][0] = ' ';
		}
	if (p1 == 'K' && x1 == 4 && x2 == 2)
		{
			s->b[3][0] = 'R';
			s->b[0][0] = ' ';
		}
	if (p1 == 'k' && x1 == 4 && x2 == 6)
		{
			s->b[5][7] = 'r';
			s->b[7][7] = ' ';
		}
	if (p1 == 'k' && x1 == 4 && x2 == 2)
		{
			s->b[3][7] = 'r';
			s->b[0][7] = ' ';
		}

	/*
	 * Moving a King waives the castling status of its castles.
	 */
	if (p1 == 'K')
		{
			s->c[0] = 'n';
			s->c[1] = 'n';
		}
	if (p1 == 'k')
		{
			s->c[2] = 'n';
			s->c[3] = 'n';
		}

	/* 
	 * Moving a Rook waives its castling status.
	 */

	if (x1 == 0 && y1 == 0 && s->c[0] == 'y') s->c[0] = 'n';
	if (x1 == 7 && y1 == 0 && s->c[1] == 'y') s->c[1] = 'n';
	if (x1 == 0 && y1 == 7 && s->c[2] == 'y') s->c[2] = 'n';
	if (x1 == 7 && y1 == 7 && s->c[3] == 'y') s->c[3] = 'n';

	/* 
	 * When pawns reach the other side, they are promoted.
	 */
	if (s->candidate_move != ChessVoidMove)
		{
			if ((p1 == 'P' && y1 == 6 && y2 == 7)
				||
				(p1 == 'p' && y1 == 1 && y2 == 0))
				{
					s->b[x2][y2] = ChessMovePPCToChar(ChessMovePPC(s->candidate_move));
				}
		}

	/*
	 * A pawn move or a piece capture reset the halfmove counter.
	 */

	if (p1 == 'p' || p1 == 'P' || p2 != ' ')
		s->halfmove_counter = 0;
	else
		s->halfmove_counter ++;
}

chess_game_status *
aux_clone_chess_game_status(const chess_game_status *s0)
{
	chess_game_status *s;

	s = (chess_game_status *) palloc0(sizeof(chess_game_status));

	memcpy(s->b[0], s0->b[0], sizeof(char) * 8);
	memcpy(s->b[1], s0->b[1], sizeof(char) * 8);
	memcpy(s->b[2], s0->b[2], sizeof(char) * 8);
	memcpy(s->b[3], s0->b[3], sizeof(char) * 8);
	memcpy(s->b[4], s0->b[4], sizeof(char) * 8);
	memcpy(s->b[5], s0->b[5], sizeof(char) * 8);
	memcpy(s->b[6], s0->b[6], sizeof(char) * 8);
	memcpy(s->b[7], s0->b[7], sizeof(char) * 8);

	memcpy(s->c, s0->c, sizeof(char) * 4);

	s->last_piece_captured = s0->last_piece_captured;

	s->previous_moves_n = s0->previous_moves_n;
	s->previous_moves = (int *) palloc0(sizeof(int) * s->previous_moves_n);
	memcpy(s->previous_moves, s0->previous_moves, sizeof(int) * s->previous_moves_n);

	s->candidate_move = s0->candidate_move;

	return s;
};

/*
 * This function reads an input "game" argument into a chess_game_status
 */

int aux_read_game(chess_game_status *s, Datum d)
{
	HeapTupleHeader h;
	bool isnull;

	char *game = NULL;

	ArrayType *moves;
	ArrayIterator moves_iterator;

	int i;
	int x1;
	int y1;

	h = DatumGetHeapTupleHeader(d);

	/*
	 * SQL object definitions which are relevant here:
	 *
	 * CREATE TYPE move AS (x1 smallint, y1 smallint, x2 smallint, y2 smallint, ppc smallint);
	 * CREATE TYPE game AS (board character(69), halfmove_counter int2, moves int2[]);
	 */

	/* game.board */
	d = GetAttributeByName(h, "board", &isnull);
	if(isnull)
		return 1;
	game = TextDatumGetCString(DatumGetBpCharP(d));
	for(x1=0;x1<8;x1++)
		for(y1=0;y1<8;y1++)
			s->b[x1][y1] = game[x1+8*y1];
	s->c[0] = game[64];
	s->c[1] = game[65];
	s->c[2] = game[66];
	s->c[3] = game[67];
	s->last_piece_captured = game[68];

	/* game.halfmove_counter */
	d = GetAttributeByName(h, "halfmove_counter", &isnull);
	if (isnull)
		return 1;
	s->halfmove_counter = DatumGetInt16(d);
					
	/* game.moves */
	d = GetAttributeByName(h, "moves", &isnull);

	if (isnull)
		{
			s->previous_moves_n = 0;
			s->previous_moves = NULL;
		}
	else
		{
			h = DatumGetHeapTupleHeader(d);
			moves = DatumGetArrayTypeP(d);
			if (ARR_NDIM(moves) == 1) 
				{
					s->previous_moves_n = ARR_DIMS(moves)[0];
					s->previous_moves = (int *) palloc0(sizeof(int) * s->previous_moves_n);
					
					moves_iterator = array_create_iterator(moves, 0);
					for (i = 0; array_iterate(moves_iterator, &d, &isnull); i++)
						{
							s->previous_moves[i] = DatumGetInt16(d);
						}
				}
		}

	return 0;
}

/*
 * This function reads a "move" argument into an int
 */

int aux_read_move(Datum d)
{
	HeapTupleHeader h;
	bool isnull;

	int x1;
	int x2;
	int y1;
	int y2;
	int ppc;

	h = DatumGetHeapTupleHeader(d);

	/*
	 * SQL object definitions which are relevant here:
	 *
	 * CREATE TYPE move AS (x1 int2, y1 int2, x2 int2, y2 int2, ppc int2);
	 */

	x1  = DatumGetInt32(GetAttributeByName(h, "x1",  &isnull));
	x2  = DatumGetInt32(GetAttributeByName(h, "x2",  &isnull));
	y1  = DatumGetInt32(GetAttributeByName(h, "y1",  &isnull));
	y2  = DatumGetInt32(GetAttributeByName(h, "y2",  &isnull));
	ppc = DatumGetInt32(GetAttributeByName(h, "ppc", &isnull));

	return ChessMove(x1,x2,y1,y2,ppc);
}

/* Enumeration of moves follows this table:
 *---------+-------------------+-----------------------------------------------------*
 * Id      | Piece             | Moves                                               *
 *---------+-------------------+-----------------------------------------------------*
 *     1-8 | Knight            | Anticlockwise, starting from 2x+y                   *
 *    9-16 | Rook/Bishop/Queen | Anticlockwise, starting from direction x            *
 *      17 | King              | The only available move                             *
 *      18 | Pawn              | Not capturing (forward), promote to Q if rank = max *
 *      19 | Pawn              | Capturing to the left, promote to Q if rank = max   *
 *      20 | Pawn              | Capturing to the right, promote to Q if rank = max  *
 *   21-23 | Pawn              | like 19-21, when rank = max, promote to R           *
 *   24-26 | Pawn              | like 19-21, when rank = max, promote to B           *
 *   27-29 | Pawn              | like 19-21, when rank = max, promote to N           *
 *---------+-------------------+-----------------------------------------------------*/

/*
 * This function rewinds the formal move iterator to the start.
 */

int
aux_chess_formal_move_rewind(chess_game_status *s)
{
	s->move_iterator = 0;
	return 0;
}

/*
 * This function finds the next formal move available, returning 0
 * iff there is none.
 */

int
aux_chess_formal_move_next(chess_game_status *s)
{

	/*
	 * Chess-specific static data
	 */

	int king_moves[][2] =
		{ 	
			{  1,  0 },
			{  1,  1 },
			{  0,  1 },
			{ -1,  1 },
			{ -1,  0 },
			{ -1, -1 },
			{  0, -1 },
			{  1, -1 },
			{  2,  0 }, /* castling kingside */
			{ -2,  0 }  /* castling queenside */
		};
	int knight_moves[][2] =
		{ 
			{  2,  1 },
			{  1,  2 },
			{ -1,  2 },
			{ -2,  1 },
			{ -2, -1 },
			{ -1, -2 },
			{  1, -2 },
			{  2, -1 }
		};
	int queen_directions[][2] =
		{
			{  1,  0 },
			{  1,  1 },
			{  0,  1 },
			{ -1,  1 },
			{ -1,  0 },
			{ -1, -1 },
			{  0, -1 },
			{  1, -1 }
		};

	/*
	 * Dynamic data 
	 */

	char side = s->previous_moves_n % 2 == 0 ? 'w' : 'b';
	char my_king   = (side == 'w') ? 'K' : 'k';
	char my_queen  = (side == 'w') ? 'Q' : 'q';
	char my_rook   = (side == 'w') ? 'R' : 'r';
	char my_bishop = (side == 'w') ? 'B' : 'b';
	char my_knight = (side == 'w') ? 'N' : 'n';
	char my_pawn   = (side == 'w') ? 'P' : 'p';

	int i, j;
	int x1=0, y1=0, x2, y2, ym, dx, dy, id, tg;

	if (s->halfmove_counter >= 50)
		{
			s->candidate_move=ChessEndOfMoves;
			return 0;
		}

	x2 = ChessMoveX2(s->move_iterator);
	y2 = ChessMoveY2(s->move_iterator);
	id = ChessMoveID(s->move_iterator);
	tg = ChessMoveTarget(s->move_iterator);
	while (s->move_iterator < ChessIteratorEnd)
		{
			/*
			 * Change target if the current one has been scanned or is
			 * not suitable.
			 */

			if (side == aux_chess_side(s->b[x2][y2])
				||
				id >= ChessMoveIDMax)
				{
					s->move_iterator = ChessMoveNextTarget(s->move_iterator);
					x2 = ChessMoveX2(s->move_iterator);
					y2 = ChessMoveY2(s->move_iterator);
					id = ChessMoveID(s->move_iterator);
					tg = ChessMoveTarget(s->move_iterator);

					continue;
				}

			/* 
			 * From now on we can assume that the target square does
			 * not contain a friendly piece, and that the current
			 * MoveID, if incremented, gives a valid MoveID.
			 */

			while (id < ChessMoveIDMax)
				{
					id++;
					switch (id)
						{
							/* 1-8: Knight */
						case 1:
						case 2:
						case 3:
						case 4:
						case 5:
						case 6:
						case 7:
						case 8:
							i = id - 1;
							x1 = x2 - knight_moves[i][0];
							y1 = y2 - knight_moves[i][1];
							if (ChessValidXY(x1,y1) && s->b[x1][y1] == my_knight)
								{
									s->move_iterator=ChessIteratorFromTgId(tg,id);
									s->candidate_move=ChessMove(x1,y1,x2,y2,0);
									return 1;
								}
							break;
							/* 9-16: Rook, Bishop, Queen */
						case 9:
						case 10:
						case 11:
						case 12:
						case 13:
						case 14:
						case 15:
						case 16:
							i = id - 9;
							dx = queen_directions[i][0];
							dy = queen_directions[i][1];
							x1 = x2;
							y1 = y2;
							for (j=1; j<8; j++)
								{
									x1 -= dx;
									y1 -= dy;
									if (s->b[x1][y1] != ' ')
										break;
								}
							if (ChessValidXY(x1,y1) && 
								(s->b[x1][y1] == my_queen                  ||
								 (s->b[x1][y1] == my_rook   && i % 2 == 0) ||
								 (s->b[x1][y1] == my_bishop && i % 2 == 1)))
								{
									s->move_iterator=ChessIteratorFromTgId(tg,id);
									s->candidate_move=ChessMove(x1,y1,x2,y2,0);
									return 1;									
								}
							break;
							/* 17: King */
						case 17:
							for (i=0;i<10;i++)
								{
									x1 = x2 - king_moves[i][0];
									y1 = y2 - king_moves[i][1];
									if (ChessValidXY(x1,y1) && s->b[x1][y1] == my_king)
										{
											/* Castling kingside */
											if (king_moves[i][0] == 2)
												{
													if (x1 == 4 &&
														y1 == 0 &&
														s->b[5][0] == ' ' &&
														s->b[6][0] == ' ' &&
														s->c[0] == 'y')
														break;
													if (x1 == 4 &&
														y1 == 7 &&
														s->b[5][7] == ' ' &&
														s->b[6][7] == ' ' &&
														s->c[1] == 'y')
														break;
													continue;
												}
											/* Castling queenside */
											if (king_moves[i][0] == -2)
												{
													if (x1 == 4 &&
														y1 == 0 &&
														s->b[3][0] == ' ' &&
														s->b[2][0] == ' ' &&
														s->b[1][0] == ' ' &&
														s->c[2] == 'y')
														break;
													if (x1 == 4 &&
														y1 == 7 &&
														s->b[3][7] == ' ' &&
														s->b[2][7] == ' ' &&
														s->b[1][7] == ' ' &&
														s->c[3] == 'y')
														break;
													continue;
												}
											break;
										}
								}
							if (i<10)
								{
									{
										s->move_iterator=ChessIteratorFromTgId(tg,id);
										s->candidate_move=ChessMove(x1,y1,x2,y2,0);
										return 1;
									}
								}
							break;
							/*
							 * 18-29: Pawn moves
							 *
							 * subcases #1:
							 * - 18-20: not promoted or promoted to Queen (depending on y2)
							 * - 21-23: promoted to Rook
							 * - 24-26: promoted to Bishop
							 * - 27-29: promoted to Knight
							 *
							 * subcases #2:
							 * - 18,21,24,27: non-capturing forward
							 * - 19,22,25,28: capturing to the left
							 * - 20,23,26,29: capturing to the right
							 */
						case 18:
						case 21:
						case 24:
						case 27:
							if (s->b[x2][y2] == ' ') /* only non-capturing */
								{
									x1 = x2;
									y1 = y2 + (side == 'w' ? -1 : 1);
									if (ChessValidXY(x1,y1) && 
										s->b[x1][y1] == my_pawn &&
										(id == 18 || y2 == (side == 'w' ? 7 : 0)))
										{
											s->move_iterator=ChessIteratorFromTgId(tg,id);
											s->candidate_move=ChessMove(x1,y1,x2,y2,
																		(id == 18 ? 0 :
																		 (id == 21 ? 1 :
																		  (id == 24 ? 2 : 3))));
											return 1;
										}
									if (id == 18 &&
										((y2 == 3 && side == 'w') ||
										 (y2 == 4 && side == 'b')))
										{
											y1 = y2 + (side == 'w' ? -2 : 2);
											ym = y2 + (side == 'w' ? -1 : 1);
											if (s->b[x1][y1] == my_pawn &&
												s->b[x1][ym] == ' ') /* ChessValid not needed here */
												{
													s->move_iterator=ChessIteratorFromTgId(tg,id);
													s->candidate_move=ChessMove(x1,y1,x2,y2,0);
													return 1;
												}
										}
								}
							break;
						case 19:
						case 20:
						case 22:
						case 23:
						case 25:
						case 26:
						case 28:
						case 29:
							if (s->b[x2][y2] != ' ') /* only capturing */
								{
									x1 = x2 + (id % 3 == 1 ? -1 : 1);
									y1 = y2 + (side == 'w' ? -1 : 1);
									if (ChessValidXY(x1,y1) && 
										s->b[x1][y1] == my_pawn &&
										(id <= 20 || y2 == (side == 'w' ? 7 : 0)))
										{
											s->move_iterator=ChessIteratorFromTgId(tg,id);
											s->candidate_move=ChessMove(x1,y1,x2,y2,
																		(id <= 20 ? 0 :
																		 (id <= 23 ? 1 :
																		  (id <= 26 ? 2 : 3))));
											return 1;
										}
								}
							break;
						default:
							ereport(ERROR, (errmsg("unsupported move ID %d", id)));
						}
				}
			
			/*
			 * updating the iterator
			 */

			s->move_iterator=ChessIteratorFromTgId(tg,id);
		}
	/*
	 * no valid move was found
	 */

	s->candidate_move=ChessEndOfMoves;
	return 0;
}

/*
 * This function decides whether the candidate move (which is assumed
 * to be a formal move) leaves its own king under attack.
 */

int
aux_chess_is_king_safe(const chess_game_status *s0)
{
	int move;
	int x2;
	int y2;
	char captured_piece;
	chess_game_status *s;

	/* clone s0 and apply the candidate move */
	s = aux_clone_chess_game_status(s0);	
	aux_chess_update_fen(s);
	aux_chess_apply_candidate_move(s);
	aux_chess_update_fen(s);

	/* check safety by looping over valid moves */
	aux_chess_formal_move_rewind(s);
	while (aux_chess_formal_move_next(s))
		{
			move = s->candidate_move;
			x2 = ChessMoveX2(move);
			y2 = ChessMoveY2(move);
			captured_piece = s->b[x2][y2];
			if (captured_piece == 'k' || captured_piece == 'K')
				{
					aux_destroy_chess_game_status(s);
					return 0;
				}
		}

	aux_destroy_chess_game_status(s);

	return 1;
}

/*
 * The following functions compute the score for a given
 * game. Positive scores means that the game is in favour of the
 * player that moves next.
 * 
 * "We" and "our" refer to the player that makes the next move, "They"
 * and "their" refer to the other player.
 *
 * The score that we compute is the combination of three subscores:
 * 
 * (1) the value of our pieces minus the value of their pieces
 * 
 * (2) the number of our available moves minus the number of their
 *      available moves
 * 
 * (3) the number of their pieces that we attack, minus the number of
 *     our pieces that they attack
 * 
 * The number in (3) is computed with multiplicities, e.g. if their
 * Rook is attacked by both our Queen and our Bishop then it is counts
 * as two.
 */

int
aux_chess_piece_value(char p)
{
	switch (p)
		{
		case 'p':
		case 'P':
			return 1;
		case 'n':
		case 'N':
			return 3;
		case 'b':
		case 'B':
			return 3;
		case 'r':
		case 'R':
			return 5;
		case 'q':
		case 'Q':
			return 9;
		default:
			return 0;
		}
}

int
aux_chess_score_available_pieces(chess_game_status *s)
{
	int x,y;
	char p;
	char our_side = s->previous_moves_n % 2 == 0 ? 'w' : 'b';
	int o = 0;
	for(x=0;x<8;x++)
		for(y=0;y<8;y++)
			{
				p = s->b[x][y];
				o += (aux_chess_side(p) == our_side ? 1 : -1)
					* aux_chess_piece_value(p);
			}
	return o;
}

int
aux_chess_score_available_moves(chess_game_status *s)
{
	int o = 0;
	chess_game_status *s1;
	int candidate_move;

	/* (1) our moves */
	candidate_move = s->candidate_move;
	aux_chess_formal_move_rewind(s);
	while (aux_chess_formal_move_next(s))
		if (aux_chess_is_king_safe(s))
			o++;
	s->candidate_move = candidate_move;

	/* (2) their moves */
	s1 = aux_clone_chess_game_status(s);
	s1->candidate_move = ChessVoidMove;
	aux_chess_apply_candidate_move(s1);
	aux_chess_formal_move_rewind(s1);
	while (aux_chess_formal_move_next(s1))
		if (aux_chess_is_king_safe(s1))
			o--;

	return o;
}

int
aux_chess_score_attacked_pieces(chess_game_status *s)
{
	/* TODO */
	return 0;
}

double
aux_chess_score(chess_game_status *s)
{
	return aux_chess_score_available_pieces(s)
		+ ChessCoeffScoreMoves * aux_chess_score_available_moves(s)
/*		+ ChessCoeffScoreAttacked * aux_chess_score_attacked_pieces(s) TODO */
		;
}

void
aux_chess_update_fen(chess_game_status *s)
{
	char *p = s->fen;
	int i, j;
	int c;
	for (j = 7; j >= 0; j--)
		{
			c = 0;
			for(i = 0; i < 8; i++)
				{
					if (s->b[i][j] == ' ')
						{
							c++;
						}
					else
						{
							if (c > 0)
								{
									sprintf(p,"%d",c);
									p++;
								}
							c = 0;
							sprintf(p,"%c",s->b[i][j]);
							p++;
						}
				}
			if (c > 0)
				{
					sprintf(p,"%d",c);
					p++;
				}
			if (j > 0)
				{
					sprintf(p,"/");
					p++;
				}
		}
	sprintf(p, " %c", s->previous_moves_n % 2 ? 'b' : 'w'); p += 2;
	if (! strncmp(s->c, "nnnn", 4))
		{
			sprintf(p, " -"); p += 2;
		}
	else
		{
			sprintf(p, " "); p++;
			if (s->c[0] == 'y') { sprintf(p, "K"); p++; }
			if (s->c[1] == 'y') { sprintf(p, "Q"); p++; }
			if (s->c[2] == 'y') { sprintf(p, "k"); p++; }
			if (s->c[3] == 'y') { sprintf(p, "q"); p++; }
		}
	/* FIXME: En passant target square is not implemented */
	sprintf(p, " - %d %d", s->halfmove_counter, 1 + s->previous_moves_n / 2);
}

/*
 * This function checks whether the king of the moving side is safe.
 */

PG_FUNCTION_INFO_V1(chess_is_king_safe);

Datum
chess_is_king_safe(PG_FUNCTION_ARGS)
{
	chess_game_status *s;
	s = (chess_game_status *) palloc0(sizeof(chess_game_status));
	aux_init_chess_game_status(s);
	if(aux_read_game(s,PG_GETARG_DATUM(0)))
		{
			ereport(ERROR, (errmsg("chess_is_king_safe: null input not allowed")));
		}
	s->candidate_move = ChessVoidMove;
	PG_RETURN_BOOL(aux_chess_is_king_safe(s) ? true : false);
}

/*
 * This function checks whether the game is ended.
 */

PG_FUNCTION_INFO_V1(chess_is_game_ended);

Datum
chess_is_game_ended(PG_FUNCTION_ARGS)
{
	chess_game_status *s;

	s = (chess_game_status *) palloc0(sizeof(chess_game_status));

	aux_init_chess_game_status(s);

	if (aux_read_game(s,PG_GETARG_DATUM(0)))
		ereport(ERROR, (errmsg("chess_is_game_ended: null input not allowed")));

	aux_chess_formal_move_rewind(s);
	while (aux_chess_formal_move_next(s))
		if (aux_chess_is_king_safe(s))
			PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(true);
}

/*
 * This function generates the list of valid moves.
 *
 * (freely inspired by the normal_rand function in the tablefunc
 * extension)
 */

PG_FUNCTION_INFO_V1(chess_valid_moves);

Datum
chess_valid_moves(PG_FUNCTION_ARGS)
{
	FuncCallContext	*cctx;
	MemoryContext	oldcontext;
    TupleDesc		tuple_desc;

	chess_game_status *s;
	int i;

	/* stuff done only on the first call of the function */
	if (SRF_IS_FIRSTCALL())
	{

		/* create a function context for cross-call persistence */
		cctx = SRF_FIRSTCALL_INIT();

		/*
		 * switch to memory context appropriate for multiple function calls
		 */
		oldcontext = MemoryContextSwitchTo(cctx->multi_call_memory_ctx);

		/* allocate memory for user context */
		s = (chess_game_status *) palloc0(sizeof(chess_game_status));

		aux_init_chess_game_status(s);

        /* Build a tuple descriptor for our result type */
        if (get_call_result_type(fcinfo, NULL, &tuple_desc) != TYPEFUNC_COMPOSITE)
            ereport(ERROR,
                    (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                     errmsg("function returning record called in context "
                            "that cannot accept type record")));

        /*
         * generate attribute metadata needed later to produce tuples
         * from Datum objects
         */
		cctx->tuple_desc = BlessTupleDesc(tuple_desc);

		/*
		 * read the input data into s
		 */
		if(aux_read_game(s,PG_GETARG_DATUM(0)))
			{
				ereport(ERROR, (errmsg("chess_valid_moves: null input not allowed")));
			}
		aux_chess_formal_move_rewind(s);

		/* save s into cctx and switch back to the old context */
		cctx->user_fctx = s;
		MemoryContextSwitchTo(oldcontext);

	}

	/* stuff done on every call of the function */
	cctx = SRF_PERCALL_SETUP();
	s = cctx->user_fctx;

	/* browse candidate moves */
	while (aux_chess_formal_move_next(s) &&
		   (! aux_chess_is_king_safe(s)));

	if (s->candidate_move >= ChessEndOfMoves) /* no more candidates */
		{
			SRF_RETURN_DONE(cctx);
		}
	else /* found a valid move */
		{
			Datum *values;
			HeapTuple tuple;
			bool *isnull;
			int move = s->candidate_move;
			s->candidate_move ++;
			s->found_moves ++;

			tuple_desc = cctx->tuple_desc;

			values = (Datum *) palloc(5 * sizeof(Datum));
			isnull = (bool *) palloc(5 * sizeof(bool));

			values[0] = Int16GetDatum(1 + ChessMoveX1(move));
			values[1] = Int16GetDatum(1 + ChessMoveY1(move));
			values[2] = Int16GetDatum(1 + ChessMoveX2(move));
			values[3] = Int16GetDatum(1 + ChessMoveY2(move));
			values[4] = Int16GetDatum(ChessMovePPC(move));
			for (i = 0; i < 5; i++)
				isnull[i] = false;

			tuple = heap_form_tuple(tuple_desc,values,isnull);
			
			SRF_RETURN_NEXT(cctx, HeapTupleGetDatum(tuple));
		}			
}

PG_FUNCTION_INFO_V1(chess_game_to_fen);

Datum
chess_game_to_fen(PG_FUNCTION_ARGS)
{
	chess_game_status *s;

	s = (chess_game_status *) palloc0(sizeof(chess_game_status));
	aux_init_chess_game_status(s);
	if(aux_read_game(s,PG_GETARG_DATUM(0)))
		{
			PG_RETURN_NULL();
		}
	else
		{
			aux_chess_update_fen(s);
			PG_RETURN_TEXT_P(cstring_to_text(s->fen));
		}
}

PG_FUNCTION_INFO_V1(chess_game_score);

Datum
chess_game_score(PG_FUNCTION_ARGS)
{
	chess_game_status *s;

	s = (chess_game_status *) palloc0(sizeof(chess_game_status));
	aux_init_chess_game_status(s);
	if(aux_read_game(s,PG_GETARG_DATUM(0)))
		{
			PG_RETURN_NULL();
		}
	else
		{
			PG_RETURN_FLOAT8(aux_chess_score(s));
		}
}
