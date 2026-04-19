.PHONY: all doc vivado lint-verilator clean test docker-build docker-run-it 

MKFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
MKFILE_DIR := $(dir $(MKFILE_PATH))
INC_DIR := ${MKFILE_DIR}/rtl/inc

CUID := $(shell id -u)
CGID := $(shell id -g)
CWD  := $(abspath $(dir $$PWD))


docker-build:
	docker build -t iic-osic-tools-plus:0.1 .

docker-run-it:
	docker run -it \
			   --user ${CUID}:${CGID} \
			   -e "UID=${CUID}" \
			   -e "GID=${CGID}" \
			   -v /etc/group:/etc/group:ro \
               -v /etc/passwd:/etc/passwd:ro \
               -v /etc/shadow:/etc/shadow:ro \
			   -v ~/.cache/:/headless/.cache:rw \
			   -v $(CWD):/foss/designs/obi \
			    iic-osic-tools-plus:0.1 -s /bin/bash
