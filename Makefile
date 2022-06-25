EXTENSION    = pgchess
EXTVERSION   = $(shell grep default_version $(EXTENSION).control | \
               sed -e "s/default_version[[:space:]]*=[[:space:]]*'\([^']*\)'/\1/")

DATA         = $(filter-out $(wildcard *--*.sql),$(wildcard *.sql))
DOCS         = $(wildcard doc/*.md)

## FIXME - regression tests are still not working
REGRESS      = $(patsubst sql/%.sql,%,$(wildcard sql/c*.sql))
#REGRESS_OPTS = --inputdir=test

MODULES      = $(patsubst %.c,%,$(wildcard src/*.c))
PG_CONFIG    = pg_config

all: $(EXTENSION)--$(EXTVERSION).sql

$(EXTENSION)--$(EXTVERSION).sql: $(EXTENSION).sql
	cp $< $@

DATA = $(wildcard *--*.sql)
EXTRA_CLEAN = $(EXTENSION)--$(EXTVERSION).sql

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
