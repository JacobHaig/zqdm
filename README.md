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


# Install ZQDM as a Dependency into your Zig Project
To add ZQDM as a dependency in your Zig project, use the following command to fetch and save it to your `zig.lock` file: 
```sh
zig fetch --save git+https://github.com/JacobHaig/zqdm
```



Then, modify your `build.zig` file to include ZQDM as a dependency:
```zig
// Add these lines to include the zqdm dependency
const zqdm_dep = b.dependency("zqdm", .{
    .target = target,
    .optimize = optimize,
});
// Add this line to get the zqdm module
const zqdm_mod = zqdm_dep.module("zqdm");

const exe = b.addExecutable(.{
    .name = "my_app",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            // Add this line to import the zqdm module
            .{ .name = "zqdm", .module = zqdm_mod },
        },
    }),
});

b.installArtifact(exe);
```


Now you can use ZQDM in your Zig project by importing it in your source files:
```zig
const std = @import("std");
const zqdm = @import("zqdm").zqdm;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var list: std.ArrayList(u8) = .{};
    try list.appendSlice(allocator, "Hello there! ");
    try list.appendSlice(allocator, "This is a demo of zqdm progress bar in Zig. ");
    try list.appendSlice(allocator, "Enjoy!\n");

    var progress_bar = zqdm(u8).new(allocator, list.items);
    while (progress_bar.next()) |val| {
        std.Thread.sleep(100000000);
        try progress_bar.write("{c}", .{val.get()});
    }
}
```