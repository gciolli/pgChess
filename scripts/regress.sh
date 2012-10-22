#!/bin/bash

TmpFile=test/sql/tmp/_.txt

f () {
    Stem=${1#test/sql/regress/}
    Stem=${Stem%.sql}
    Input=test/sql/regress/${Stem}.sql
    Expected=test/sql/expected/${Stem}.txt
    Actual=test/sql/tmp/${Stem}.txt
    mkdir -p test/sql/tmp
    psql -vVERBOSITY=terse -f $Input 2>$Actual >/dev/null
    if diff $Expected $Actual > $TmpFile ; then
	echo "$(date +%s.%N) [OK] $Stem"
    else
	echo "$(date +%s.%N) [KO] $Stem"	
	cat $TmpFile
	rm -f $TmpFile
    fi
}

echo "$(date +%s.%N) [--] BEGIN"
f score-knight
f score-pawn
f score-rook
f score-bishop
f score-queen
f score-mate
f full-game-10
f full-game-3d2
f castling-K
echo "$(date +%s.%N) [--] END"
