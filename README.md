pgchess 0.1.4
=============

pgchess is a PostgreSQL 9.1+ extension for the game of Chess.

Build
-----

To build **pgchess**, just type:

    make
    make installcheck
    make install

If you encounter an error such as:

    "Makefile", line 8: Need an operator

you need to use GNU make, which may well be installed on your system as
`gmake`:

    gmake
    gmake install
    gmake installcheck

If you encounter an error such as:

    make: pg_config: Command not found

be sure that you have `pg_config` installed and in your path. If you
used a package management system such as RPM to install PostgreSQL, be
sure that the `-devel` package is also installed. If necessary tell the
build process where to find it:

    env PG_CONFIG=/path/to/pg_config make && make installcheck && make install

Usage
-----

Once pgchess is installed, you can add it to a database. You must be
running PostgreSQL 9.1 or greater, so it's a simple as connecting to a
database as a super user and running:

    CREATE EXTENSION pgchess;

Dependencies
------------

Strictly speaking, extension pgchess has no dependencies other than
PostgreSQL and PL/pgSQL.

However, some generic functionalities have been placed in a separate
extension **pg2podg**, so that they can be reused by extensions
implementing other two-player open deterministic games such as
Naughts-and-Crosses, Nim, etc.

Extension pg2podg is therefore recommended, as well as required for some
of pgchess functionalities, including the capability to run regression
tests and to play a game of Chess.

Both pgchess and pg2podg are available via [the PostgreSQL Extension
Network](http://pgxn.org).

Upgrades from previous versions
-------------------------------

Currently the only way to upgrade from a previous version of pgchess is
to drop the extension, uninstall the old version, install the new
version and finally (re)create the extension.

In particular, any extensions that depend on pgchess or on some of its
objects need to be dropped and recreated.

Please notice that the pgchess extension so far contains only types,
functions and operators.

Copyright and Licence
---------------------

Copyright (c) 2010, 2011, 2012 Gianni Ciolli.

This module is free software; you can redistribute it and/or modify it
under the [GNU General Public License version 3 or
later](http://www.gnu.org/copyleft/gpl.html).
