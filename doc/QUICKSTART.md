pgchess Quickstart
==================

Notes
-----

We require extensions **pgchess** and **pg2podg**.

The procedure described in this document has been tested on versions
0.1.4 of both packages, installed on a PostgreSQL 9.2 server.

The SQL files in the `test/sql/play` directory make use of the
convenient `\ir` meta command, which was introduced on PostgreSQL 9.2;
on PostgreSQL 9.1 it is necessary to rewrite such files using the `\i`
meta command. Future versions of this extension will include a 9.1
version of these files as well.

Step 1
------

Install both extensions on a PostgreSQL 9.1+ server. You can use
`pgxnclient`, for instance:

    pgxnclient install pgchess
    pgxnclient install pg2podg

Step 2
------

Download and unpack the `pgchess` archive, which contains some
additional files:

    pgxnclient download pgchess
    unzip pgchess-0.1.4.zip
    cd pgchess-0.1.4/test/sql

Step 3
------

Create the database objects, in the following order:

    gianni=# CREATE EXTENSION pgchess;
    CREATE EXTENSION
    gianni=# CREATE EXTENSION pg2podg;
    CREATE EXTENSION

Step 4
------

Load a default game in the chessboard:

    \i play/new-game.sql

Step 5
------

View the game in FEN notation

    gianni=# select %% game from status;
                             ?column?                         
    ----------------------------------------------------------
     rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1
    (1 row)

Step 5a (optional)
------------------

If you are using a VT100-compatible terminal, you can use an enhanced
graphical display.

First make sure that the background is lighter than the foreground (e.g.
black on white); then issue

    gianni=# \pset format unaligned
    Output format is unaligned.

and check that it is working by displaying the current game:

    gianni=# select # game from status;
    ?column?
     ♜ ♞ ♝ ♛ ♚ ♝ ♞ ♜  8
     ♟ ♟ ♟ ♟ ♟ ♟ ♟ ♟  7
                      6
                      5
                      4
                      3
     ♙ ♙ ♙ ♙ ♙ ♙ ♙ ♙  2
     ♖ ♘ ♗ ♕ ♔ ♗ ♘ ♖  1
     a b c d e f g h  
    (1 row)

Step 6
------

Now you can start a CPU v CPU game:

    \i play/PG_v_PG.sql

you can interrupt the game with CTRL-C. Since each half-move is executed
in a separate transaction, the game will be left in the state
corresponding to the last completed move.
