const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

pub fn zqdm(comptime T: type) type {
    const Zqdm = struct {
        const Self = @This();

        const filled_char: []const u8 = "█";
        const empty_char: []const u8 = "░";

        slice: []const T,
        element: usize,
        terminal_width: usize,

        allocator: std.mem.Allocator,
        io: Io,
        stdout_backlog: std.ArrayListUnmanaged(u8),
        start_time: std.time.Instant = undefined,

        pub fn new(allocator: std.mem.Allocator, io: Io, slice: []const T) !Self {
            var terminal_width: usize = 80;

            switch (builtin.os.tag) {
                .windows => {
                    // Enable UTF-8 output - required for windows terminal to display unicode characters correctly
                    _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);

                    // Get terminal width
                    var buf: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
                    _ = std.os.windows.kernel32.GetConsoleScreenBufferInfo(Io.File.stdout().handle, &buf);
                    const diff: i16 = buf.srWindow.Right - buf.srWindow.Left;
                    terminal_width = if (diff > 0) @intCast(diff) else 80;
                },
                .linux => {
                    // Try to get terminal size using TIOCGWINSZ ioctl
                    const TIOCGWINSZ = 0x5413;
                    const winsize = extern struct {
                        ws_row: u16,
                        ws_col: u16,
                        ws_xpixel: u16,
                        ws_ypixel: u16,
                    };

                    var ws: winsize = undefined;
                    const fd = Io.File.stdout().handle;
                    _ = std.os.linux.syscall3(.ioctl, @as(usize, @intCast(fd)), TIOCGWINSZ, @intFromPtr(&ws));

                    terminal_width = ws.ws_col;
                },
                else => @compileError("zqdm: OS not supported. Feel free to contribute!"),
            }

            if (terminal_width == 0) {
                terminal_width = 80; // Fallback to 80 if we couldn't get terminal width
            }

            return Self{
                .slice = slice,
                .element = 0,
                .terminal_width = terminal_width,
                .allocator = allocator,
                .io = io,
                .stdout_backlog = .{},
                .start_time = try std.time.Instant.now(),
            };
        }

        pub fn deinit(self: *Self) void {
            self.stdout_backlog.deinit(self.allocator);
        }

        pub fn get(self: *Self) T {
            std.debug.assert(self.element > 0); // get() called before first next()
            return self.slice[self.element - 1];
        }

        pub fn next(self: *Self) !?*Self {
            // Check if we've reached the end
            if (self.element >= self.slice.len) return null;
            self.element += 1;

            // Update and display the progress bar
            try self.display_progress_bar();

            return self;
        }

        fn display_progress_bar(self: *Self) !void {
            var stderr_buffer: [1024]u8 = undefined;
            var stderr_writer = Io.File.stderr().writer(self.io, &stderr_buffer);
            const stderr = &stderr_writer.interface;

            const now = try std.time.Instant.now();
            const elapsed_nanoseconds = now.since(self.start_time);
            const elapsed_milliseconds = @divTrunc(elapsed_nanoseconds, 1_000_000);

            // print a carriage return to overwrite the previous line
            try stderr.print("\r", .{});

            const print_percentage_width: usize = 7; // Width for percentage display (e.g., "100.00%")

            // Calculate percentage
            const percentage: f32 = @as(f32, @floatFromInt(self.element)) / @as(f32, @floatFromInt(self.slice.len));
            var percentage_buf = [_]u8{0} ** 64;
            const percentage_fmt = try self.print_percentage(&percentage_buf, percentage);

            // Info string
            var info_buf = [_]u8{0} ** 256;
            const info_fmt = try self.format_estimated_time_remaining(&info_buf, percentage, elapsed_milliseconds);

            // Progress bar
            var progress_bar_buf = [_]u8{0} ** (512 * filled_char.len);
            const overhead = print_percentage_width + info_fmt.len;
            const bar_width: usize = if (self.terminal_width > overhead + 4)
                self.terminal_width - overhead
            else
                4; // minimum: " [] "
            const progress_bar_fmt = try self.print_progress_bar(&progress_bar_buf, percentage, bar_width);

            // Print all the components
            try stderr.print("{s}", .{percentage_fmt});
            try stderr.print("{s}", .{progress_bar_fmt});
            try stderr.print("{s}", .{info_fmt});

            // If we're done iterating, print a newline to move the cursor to the next line
            if (self.element == self.slice.len) {
                try stderr.print("\n", .{});
            }

            try stderr.flush();
        }

        fn print_percentage(_: *Self, buf: []u8, percentage: f32) ![]u8 {
            // Print percentage with 2 decimal places, right-aligned in a field of width 7
            return try std.fmt.bufPrint(buf, "{d:>6.2}%", .{percentage * 100.0});
        }

        fn format_estimated_time_remaining(self: *Self, buf: []u8, percentage: f32, elapsed_milliseconds: u64) ![]u8 {
            // 13/13 [00:01<00:00,  9.94it/s]
            // Print elapsed time, estimated remaining time, and iteration speed

            // Current index and total
            const index = self.element;
            const total = self.slice.len;
            var progress_buf = [_]u8{0} ** 64;
            const progress_fmt = try std.fmt.bufPrint(&progress_buf, "{d}/{d}", .{ index, total });

            // Calculate elapsed time components
            const elapsed_seconds = @divTrunc(elapsed_milliseconds, 1000);
            const elapsed_minutes = @divTrunc(elapsed_seconds, 60);
            const elapsed_hours = @divTrunc(elapsed_minutes, 60);
            var elapsed_buf = [_]u8{0} ** 64;
            var elapsed_fmt: []u8 = undefined;
            if (elapsed_hours > 0) {
                elapsed_fmt = try std.fmt.bufPrint(&elapsed_buf, "{d:02}:{d:02}:{d:02}", .{
                    elapsed_hours,
                    @mod(elapsed_minutes, 60),
                    @mod(elapsed_seconds, 60),
                });
            } else {
                elapsed_fmt = try std.fmt.bufPrint(&elapsed_buf, "{d:02}:{d:02}", .{
                    @mod(elapsed_minutes, 60),
                    @mod(elapsed_seconds, 60),
                });
            }

            // Calculate estimated remaining time
            var remaining_seconds: u64 = 0;
            if (percentage > 0.0) {
                const estimated_total_time: u64 = @intFromFloat(@as(f32, @floatFromInt(elapsed_milliseconds)) / percentage);
                const estimated_remaining_time = estimated_total_time - elapsed_milliseconds;
                remaining_seconds = @divTrunc(estimated_remaining_time, 1000);
            }
            const remaining_minutes = @divTrunc(remaining_seconds, 60);
            const remaining_hours = @divTrunc(remaining_minutes, 60);
            var remaining_buf = [_]u8{0} ** 64;
            var remaining_fmt: []u8 = undefined;
            if (remaining_hours > 0) {
                remaining_fmt = try std.fmt.bufPrint(&remaining_buf, "{d:02}:{d:02}:{d:02}", .{
                    remaining_hours,
                    @mod(remaining_minutes, 60),
                    @mod(remaining_seconds, 60),
                });
            } else {
                remaining_fmt = try std.fmt.bufPrint(&remaining_buf, "{d:02}:{d:02}", .{
                    @mod(remaining_minutes, 60),
                    @mod(remaining_seconds, 60),
                });
            }

            // Calculate iteration speed
            const speed: f32 = if (elapsed_seconds > 0) @as(f32, @floatFromInt(index)) / @as(f32, @floatFromInt(elapsed_seconds)) else 0.0;

            // Combine all parts into the final format
            return try std.fmt.bufPrint(buf, "{s} [{s} < {s}, {d:.2}it/s]", .{
                progress_fmt,
                elapsed_fmt,
                remaining_fmt,
                speed,
            });
        }

        fn print_progress_bar(_: *Self, buf: []u8, percentage: f32, progress_bar_width: usize) ![]u8 {
            var pos: usize = 0;

            // Bracket start
            const start = try std.fmt.bufPrint(buf[pos..], " [", .{});
            pos += start.len;

            // Calculate dimensions
            const bracket_width: usize = 4;
            const corrected_progress_bar_width = if (progress_bar_width > bracket_width)
                progress_bar_width - bracket_width
            else
                0;
            const progress_width_f32: f32 = @floatFromInt(corrected_progress_bar_width);
            const print_width: usize = @intFromFloat(percentage * progress_width_f32);

            // Filled part
            for (0..print_width) |_| {
                const filled = try std.fmt.bufPrint(buf[pos..], "{s}", .{filled_char});
                pos += filled.len;
            }

            // Empty part
            for (print_width..corrected_progress_bar_width) |_| {
                const empty = try std.fmt.bufPrint(buf[pos..], "{s}", .{empty_char});
                pos += empty.len;
            }

            // Bracket end
            const end = try std.fmt.bufPrint(buf[pos..], "] ", .{});
            pos += end.len;

            return buf[0..pos];
        }

        /// Like tqdm.write: prints a message above the progress bar, then redraws the bar.
        pub fn write(self: *Self, comptime fmt: []const u8, args: anytype) !void {
            // Write the user message to stdout_backlog, once its done iterating we'll print it out
            const msg = try std.fmt.allocPrint(self.allocator, fmt, args);
            defer self.allocator.free(msg);
            try self.stdout_backlog.appendSlice(self.allocator, msg);

            // If we're done iterating, print the backlog and clear it
            if (self.element == self.slice.len) {

                // Print to stdout
                var stdout_buffer: [1024]u8 = undefined;
                var stdout_writer = Io.File.stdout().writer(self.io, &stdout_buffer);
                const stdout = &stdout_writer.interface;

                try stdout.print("{s}", .{self.stdout_backlog.items});
                try stdout.flush();

                self.stdout_backlog.clearRetainingCapacity();
            }
        }
    };

    return Zqdm;
}

test "Static Slice" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    const slice: []const u8 = "Hello there! This is a demo of zqdm progress bar in Zig. Enjoy!\n";

    const io = Io.Threaded.global_single_threaded.io();
    var progress_bar = try zqdm(u8).new(allocator, io, slice);
    defer progress_bar.deinit();
    while (try progress_bar.next()) |val| {
        try std.Io.Clock.Duration.sleep(.{ .clock = .awake, .raw = .fromNanoseconds(100) }, io);
        try progress_bar.write("{c}", .{val.get()});
    }
}

test "Dynamic List" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var list: std.ArrayList(u8) = .{};
    try list.appendSlice(allocator, "Hello there! ");
    try list.appendSlice(allocator, "This is a demo of zqdm progress bar in Zig. ");
    try list.appendSlice(allocator, "Enjoy!\n");

    const io = Io.Threaded.global_single_threaded.io();
    var progress_bar = try zqdm(u8).new(allocator, io, list.items);
    defer progress_bar.deinit();
    while (try progress_bar.next()) |val| {
        try std.Io.Clock.Duration.sleep(.{ .clock = .awake, .raw = .fromNanoseconds(100) }, io);
        try progress_bar.write("{c}", .{val.get()});
    }
}
