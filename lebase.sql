-- Tabell over løp
CREATE TABLE race (
	race SERIAL PRIMARY KEY,
	name VARCHAR(64),
	"date" DATE,
	procyclingstats_slug VARCHAR(128),

	UNIQUE (procyclingstats_slug)
);

GRANT SELECT, UPDATE, INSERT, DELETE ON race TO lebase;
GRANT SELECT, UPDATE ON race_race_seq TO lebase;

-- Etappetype
CREATE TYPE stage_type AS ENUM ('NORMAL', 'ITT', 'TTT');

-- Tabell over etapper
CREATE TABLE stage (
	stage SERIAL PRIMARY KEY,
	race INTEGER REFERENCES race ON DELETE CASCADE
	"date" DATE NOT NULL,
	"start" TIME,
	"finish" TIME,
	"type" stage_type,
	name VARCHAR(64) NOT NULL,
	length REAL,
	prologue BOOLEAN,
	procyclingstats_slug VARCHAR(128),

	UNIQUE (procyclingstats_slug)
);

GRANT SELECT, UPDATE, INSERT, DELETE ON stage TO lebase;
GRANT SELECT, UPDATE ON stage_stage_seq TO lebase;

-- Tabell over ryttere
CREATE TABLE rider (
	rider SERIAL PRIMARY KEY,
	name VARCHAR(64),
	birth_date DATE,
	procyclingstats_slug VARCHAR(64),

	UNIQUE (procyclingstats_slug)
);

GRANT SELECT, UPDATE, INSERT, DELETE ON rider TO lebase;
GRANT SELECT, UPDATE ON rider_rider_seq TO lebase;

-- Linjetype
CREATE TYPE line_type AS ENUM ('FINISH', 'SPRINT', 'MOUNTAIN');

CREATE TABLE line (
	line SERIAL PRIMARY KEY,
	stage INTEGER REFERENCES stage NOT NULL ON DELETE CASCADE,
	"type" line_type NOT NULL,
	name VARCHAR(64),
	length REAL,
	category INTEGER
);

CREATE UNIQUE INDEX one_finish ON line (stage) WHERE type = 'FINISH';

GRANT SELECT, UPDATE, INSERT, DELETE ON line TO lebase;
GRANT SELECT, UPDATE ON line_line_seq TO lebase;

-- Tabell over linjekryssinger
CREATE TABLE rider_line (
	rider INTEGER REFERENCES rider NOT NULL,
	line INTEGER REFERENCES line NOT NULL ON DELETE CASCADE,
	"number" INTEGER NOT NULL,
	time INTERVAL,

	UNIQUE (rider, line)
);

GRANT SELECT, UPDATE, INSERT, DELETE ON rider_line TO lebase;

-- Tabell over lag
CREATE TABLE team (
	team SERIAL PRIMARY KEY,
	name VARCHAR(64),
	procyclingstats_slug VARCHAR(64) UNIQUE,

	UNIQUE (name)
);

GRANT SELECT, UPDATE, INSERT, DELETE ON team TO lebase;
GRANT SELECT, UPDATE ON team_team_seq TO lebase;

-- Tabell over målganger for TTT
CREATE TABLE team_line (
	team INTEGER REFERENCES team,
	line INTEGER REFERENCES line,
	"number" INTEGER NOT NULL,
	time INTERVAL,

	UNIQUE (team, line)
);

GRANT SELECT, UPDATE, INSERT, DELETE ON team_line TO lebase;

-- Tabell over deltagelser
CREATE TABLE rider_race (
	rider INTEGER REFERENCES rider,
	race INTEGER REFERENCES race ON DELETE CASCADE,
	team INTEGER REFERENCES team,

	-- FIXME: Ensure that this exists when inserting into rider_line
	UNIQUE (rider, race)
);

GRANT SELECT, UPDATE, INSERT, DELETE ON rider_race TO lebase;

