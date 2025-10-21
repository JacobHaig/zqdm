# zqdm

A progress bar library for Zig, inspired by Python's tqdm.

## Building and Running

### Local Development

```bash
# Build in debug mode
zig build -Doptimize=Debug

# Build in release mode
zig build -Doptimize=ReleaseFast

# Run the demo
zig build run
```

### Docker

This is a simple Docker setup to build and run the project in a Linux x86_64 environment for testing.

```bash
# Build the Docker image
docker build -t zqdm .

# Run the container
docker run -d --rm --name zqdm zqdm

# To stop the container
docker kill zqdm
```

The Docker image builds the project for Linux x86_64 and creates a lightweight runtime container.
