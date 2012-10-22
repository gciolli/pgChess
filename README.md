pgchess 0.1.0
=============

This library contains a single PostgreSQL extension dedicated to the
game of Chess.

To build pgchess, just do this:

    make
    make installcheck
    make install

If you encounter an error such as:

    "Makefile", line 8: Need an operator

You need to use GNU make, which may well be installed on your system as
`gmake`:

    gmake
    gmake install
    gmake installcheck

If you encounter an error such as:

    make: pg_config: Command not found

Be sure that you have `pg_config` installed and in your path. If you used a
package management system such as RPM to install PostgreSQL, be sure that the
`-devel` package is also installed. If necessary tell the build process where
to find it:

    env PG_CONFIG=/path/to/pg_config make && make installcheck && make install

Once pgchess is installed, you can add it to a database. You must be
running PostgreSQL 9.1.0 or greater, so it's a simple as connecting to
a database as a super user and running:

    CREATE EXTENSION pgchess;

Dependencies
------------

This extension has no dependencies other than PostgreSQL and PL/pgSQL.

Copyright and License
---------------------

Copyright (c) 2010-2012 Gianni Ciolli.

This module is free software; you can redistribute it and/or modify it
under the [GNU General Public License version 3 or
later](http://www.gnu.org/copyleft/gpl.html).
