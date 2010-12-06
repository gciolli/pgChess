-- pgchess.sql : a Chess player in PostgreSQL
-- Copyright (C) 2010 Gianni Ciolli <gianni.ciolli@2ndQuadrant.it>
-- 
-- This program is free software: you can redistribute it and/or
-- modify it under the terms of the GNU General Public License as
-- published by the Free Software Foundation, either version 3 of the
-- License, or (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful, but
-- WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
-- General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

------------------------------------------------------------

SET search_path = chess, public;

\pset format unaligned
\pset tuples_only on
\set VERBOSITY terse

\o varfile1.sql
SELECT another_move(1,1);
\o
\i varfile1.sql
