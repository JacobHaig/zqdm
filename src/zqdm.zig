const std = @import("std");
const builtin = @import("builtin");
// const zqdm = @import("zqdm");
const unicode = @import("std").unicode;
const Io = @import("std").Io;

pub fn zqdm(comptime T: type) type {
    const Zqdm = struct {
        const Self = @This();

        const filled_char: []const u8 = "█";
        const empty_char: []const u8 = "░";

        slice: []const T,
        element: usize,
        terminal_width: usize,

        allocator: std.mem.Allocator,
        stdout_backlog: std.ArrayList(u8),
        start_time: std.time.Instant = undefined,

        stderr: *Io.Writer = undefined,

        pub fn new(allocator: std.mem.Allocator, slice: []const T) Self {
            var terminal_width: usize = undefined;

            switch (builtin.os.tag) {
                .windows => {
                    // Enable UTF-8 output - required for windows terminal to display unicode characters correctly
                    _ = std.os.windows.kernel32.SetConsoleOutputCP(65001);

                    // Get terminal width
                    var buf: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
                    _ = std.os.windows.kernel32.GetConsoleScreenBufferInfo(std.fs.File.stdout().handle, &buf);
                    terminal_width = @intCast(buf.srWindow.Right - buf.srWindow.Left + 1);
                },
                else => @panic("Only Windows is supported for now. Feel free to contribute!"),
            }

            return Self{
                .slice = slice,
                .element = 0,
                .terminal_width = terminal_width,
                .allocator = allocator,
                .stdout_backlog = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable,
                .start_time = std.time.Instant.now() catch unreachable,
            };
        }

        pub fn get(self: *Self) T {
            return self.slice[self.element - 1];
        }

        pub fn next(self: *Self) ?*Self {
            if (self.element >= self.slice.len) return null;
            self.element += 1;

            self.display();

            return self;
        }

        pub fn display(self: *Self) void {
            var stderr_buffer: [1024]u8 = undefined;
            var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
            const stderr = &stderr_writer.interface;
            self.stderr = stderr;

            const now = std.time.Instant.now() catch unreachable;
            const elapsed_nanoseconds = now.since(self.start_time);
            const elapsed_milliseconds = @divTrunc(elapsed_nanoseconds, 1_000_000);

            // print a carriage return to overwrite the previous line
            self.stderr.print("\r", .{}) catch unreachable;

            const print_percentage_width: usize = 7; // Width for percentage display (e.g., "100.00%")
            // const print_estimated_time_width: usize = 50; // Width for estimated time display (e.g., " 13/13 [00:01<00:00,  9.94it/s]")

            const percentage: f32 = @as(f32, @floatFromInt(self.element)) / @as(f32, @floatFromInt(self.slice.len));

            var percentage_buf = [_]u8{0} ** 64;
            const percentage_fmt = self.print_percentage(&percentage_buf, percentage);

            var info_buf = [_]u8{0} ** 256;
            const info_fmt = self.format_estimated_time_remaining(&info_buf, percentage, elapsed_milliseconds);

            var progress_bar_buf = [_]u8{0} ** (512 * filled_char.len);
            const progress_bar_fmt = self.print_progress_bar(&progress_bar_buf, percentage, self.terminal_width - print_percentage_width - info_fmt.len);

            self.stderr.print("{s}", .{percentage_fmt}) catch unreachable;
            self.stderr.print("{s}", .{progress_bar_fmt}) catch unreachable;
            self.stderr.print("{s}", .{info_fmt}) catch unreachable;

            // If we're done iterating, print a newline to move the cursor to the next line
            if (self.element == self.slice.len) {
                self.stderr.print("\n", .{}) catch unreachable;
            }

            self.stderr.flush() catch unreachable;
        }

        fn print_percentage(self: *Self, buf: []u8, percentage: f32) []u8 {
            _ = self; // I prefer to keep the method signature consistent
            // Print percentage with 2 decimal places, right-aligned in a field of width 7
            return std.fmt.bufPrint(buf, "{d:>6.2}%", .{percentage * 100.0}) catch unreachable;
        }

        pub fn format_estimated_time_remaining(self: *Self, buf: []u8, percentage: f32, elapsed_milliseconds: u64) []u8 {
            // 13/13 [00:01<00:00,  9.94it/s]
            // Print elapsed time, estimated remaining time, and iteration speed

            // Current index and total
            const index = self.element;
            const total = self.slice.len;
            var progress_buf = [_]u8{0} ** 64;
            const progress_fmt = std.fmt.bufPrint(&progress_buf, "{d}/{d}", .{ index, total }) catch unreachable;

            // Calculate elapsed time components
            const elapsed_seconds = @divTrunc(elapsed_milliseconds, 1000);
            const elapsed_minutes = @divTrunc(elapsed_seconds, 60);
            const elapsed_hours = @divTrunc(elapsed_minutes, 60);
            var elapsed_buf = [_]u8{0} ** 64;
            var elapsed_fmt: []u8 = undefined;
            if (elapsed_hours > 0) {
                elapsed_fmt = std.fmt.bufPrint(&elapsed_buf, "{d:02}:{d:02}:{d:02}", .{
                    elapsed_hours,
                    @mod(elapsed_minutes, 60),
                    @mod(elapsed_seconds, 60),
                }) catch unreachable;
            } else {
                elapsed_fmt = std.fmt.bufPrint(&elapsed_buf, "{d:02}:{d:02}", .{
                    @mod(elapsed_minutes, 60),
                    @mod(elapsed_seconds, 60),
                }) catch unreachable;
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
                remaining_fmt = std.fmt.bufPrint(&remaining_buf, "{d:02}:{d:02}:{d:02}", .{
                    remaining_hours,
                    @mod(remaining_minutes, 60),
                    @mod(remaining_seconds, 60),
                }) catch unreachable;
            } else {
                remaining_fmt = std.fmt.bufPrint(&remaining_buf, "{d:02}:{d:02}", .{
                    @mod(remaining_minutes, 60),
                    @mod(remaining_seconds, 60),
                }) catch unreachable;
            }

            // Calculate iteration speed
            const speed: f32 = if (elapsed_seconds > 0) @as(f32, @floatFromInt(index)) / @as(f32, @floatFromInt(elapsed_seconds)) else 0.0;

            // Combine all parts into the final format
            return std.fmt.bufPrint(buf, " {s} [{s} < {s}, {d:.2}it/s]", .{
                progress_fmt,
                elapsed_fmt,
                remaining_fmt,
                speed,
            }) catch unreachable;
        }

        fn print_progress_bar(self: *Self, buf: []u8, percentage: f32, progress_bar_width: usize) []u8 {
            _ = self; // I prefer to keep the method signature consistent
            var pos: usize = 0;

            // Bracket start
            const start = std.fmt.bufPrint(buf[pos..], " [", .{}) catch unreachable;
            pos += start.len;

            // Calculate dimensions
            const bracket_width: usize = 4;
            const corrected_progress_bar_width = progress_bar_width - bracket_width;
            const progress_width_f32: f32 = @floatFromInt(corrected_progress_bar_width);
            const print_width: usize = @intFromFloat(percentage * progress_width_f32);

            // Filled part
            for (0..print_width) |_| {
                const filled = std.fmt.bufPrint(buf[pos..], "{s}", .{filled_char}) catch unreachable;
                pos += filled.len;
            }

            // Empty part
            for (print_width..corrected_progress_bar_width) |_| {
                const empty = std.fmt.bufPrint(buf[pos..], "{s}", .{empty_char}) catch unreachable;
                pos += empty.len;
            }

            // Bracket end
            const end = std.fmt.bufPrint(buf[pos..], "] ", .{}) catch unreachable;
            pos += end.len;

            return buf[0..pos];
        }

        /// Like tqdm.write: prints a message above the progress bar, then redraws the bar.
        pub fn write(self: *Self, comptime fmt: []const u8, args: anytype) !void {
            // Write the user message to stdout_backlog, once its done iterating we'll print it out
            const msg = try std.fmt.allocPrint(self.allocator, fmt, args);
            _ = try self.stdout_backlog.appendSlice(self.allocator, msg);

            // If we're done iterating, print the backlog and clear it
            if (self.element == self.slice.len) {

                // Print to stdout
                var stdout_buffer: [1024]u8 = undefined;
                var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
                const stdout = &stdout_writer.interface;

                stdout.print("{s}", .{self.stdout_backlog.items}) catch unreachable;
                stdout.flush() catch unreachable;

                self.stdout_backlog.deinit(self.allocator);
                self.stdout_backlog = try std.ArrayList(u8).initCapacity(self.allocator, 0);
            }
            return;
        }
    };

    return Zqdm;
}
