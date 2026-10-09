image-build:
	docker build --platform=linux/amd64 . -t cs2-modded-server:latest

run:
	docker run --platform=linux/amd64  -v ${PWD}/cs2:/home/steam/cs2 cs2-modded-server:latest 

run-bash:
	docker run -it --rm --platform=linux/amd64 --entrypoint=/bin/bash -v ${PWD}/cs2:/home/steam/cs2 cs2-modded-server:latest 
