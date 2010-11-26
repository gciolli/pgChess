#!/bin/bash
psql \
    --cluster 9.0/main \
    -f dev_pgchess.sql \
    > run_chess_game.log 2>&1
