CC = gcc
CFLAGS = -O3 -no-pie -Wall
LDFLAGS = -lm

TARGET = eye_asm
SRC = eye.s

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) $(SRC) -o $(TARGET) $(LDFLAGS)

clean:
	rm -f $(TARGET)

run: $(TARGET)
	./$(TARGET)

.PHONY: all clean run
