# Use Alpine Linux as base for a smaller image
FROM alpine:3.19 AS builder

# Install dependencies needed to download and run Zig
RUN apk add --no-cache \
    curl \
    xz \
    tar

# Set the Zig version - using a stable version that meets minimum requirements
ENV ZIG_VERSION=0.15.2

# Download and install Zig
RUN curl -L "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" -o zig.tar.xz \
    && tar -xf zig.tar.xz \
    && mv zig-x86_64-linux-${ZIG_VERSION} /opt/zig \
    && rm zig.tar.xz

# Add Zig to PATH
ENV PATH="/opt/zig:${PATH}"

# Set working directory
WORKDIR /app

# Copy source files
COPY build.zig build.zig.zon ./
COPY src/ ./src/

# Build the project for Linux x86_64 with ReleaseFast optimization
RUN zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu

# Create a minimal runtime image
FROM alpine:3.19 AS runtime

# Install minimal runtime dependencies (glibc compatibility)
RUN apk add --no-cache libc6-compat

# Create a non-root user for security
RUN addgroup -g 1001 -S zqdm && \
    adduser -S -D -H -u 1001 -h /app -s /sbin/nologin -G zqdm -g zqdm zqdm

# Copy the built binary from the builder stage
COPY --from=builder /app/zig-out/bin/zqdm /usr/local/bin/zqdm

# Make sure the binary is executable
RUN chmod +x /usr/local/bin/zqdm

# Switch to non-root user
USER zqdm

# Set the entrypoint
ENTRYPOINT ["zqdm"]