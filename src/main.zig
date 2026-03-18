const std = @import("std");
const zqdm = @import("zqdm").zqdm;

pub fn main() !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var list: std.ArrayList(u8) = .{};
    try list.appendSlice(allocator, "Hello there! ");
    try list.appendSlice(allocator, "This is a demo of zqdm progress bar in Zig. ");
    try list.appendSlice(allocator, "Enjoy!\n");

    var progress_bar = try zqdm(u8).new(allocator, io, list.items);
    defer progress_bar.deinit();
    while (try progress_bar.next()) |val| {
        try std.Io.Clock.Duration.sleep(.{ .clock = .awake, .raw = .fromSeconds(1) }, io);
        try progress_bar.write("{c}", .{val.get()});
    }
}
