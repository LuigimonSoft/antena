CC = xcrun clang
CFLAGS = -std=c11 -Wall -Wextra -Werror -O2 -mmacosx-version-min=14.0
LDLIBS = -framework IOKit -framework CoreFoundation

.PHONY: all probe clean test
all: build/kworld-tv build/kworld-probe
build/kworld-tv: Sources/probe.c Sources/frontend.c Sources/frontend.h Sources/capture.c Sources/capture.h Sources/transport_stream.c Sources/transport_stream.h
	mkdir -p build
	$(CC) $(CFLAGS) Sources/probe.c Sources/frontend.c Sources/capture.c Sources/transport_stream.c $(LDLIBS) -o $@
build/kworld-probe: build/kworld-tv
	ln -sf kworld-tv $@
probe: all
	./build/kworld-probe
clean:
	rm -f build/kworld-probe build/kworld-tv build/transport-stream-test build/program-guide-test
test: all
	$(CC) $(CFLAGS) -fsanitize=address,undefined -g -I Sources Tests/transport_stream_test.c Sources/transport_stream.c -o build/transport-stream-test
	./build/transport-stream-test
	./script/antena_tools.sh verify-firmware
	xcrun swiftc -module-cache-path build/tools/module-cache Antena/Models/BroadcastProgram.swift Antena/Services/ProgramGuideDecoder.swift Tests/ProgramGuideTests.swift -o build/program-guide-test
	./build/program-guide-test
