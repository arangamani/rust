// A port of the simplistic benchmark from
//
//    http://github.com/PaulKeeble/ScalaVErlangAgents
//
// I *think* it's the same, more or less.

use std;
import std::io::writer;
import std::io::writer_util;

enum request {
    get_count,
    bytes(uint),
    stop
}

fn server(requests: comm::port<request>, responses: comm::chan<uint>) {
    let count = 0u;
    let done = false;
    while !done {
        alt comm::recv(requests) {
          get_count { comm::send(responses, copy count); }
          bytes(b) { count += b; }
          stop { done = true; }
        }
    }
    comm::send(responses, count);
}

fn run(args: [str]) {
    let from_child = comm::port();
    let to_parent = comm::chan(from_child);
    let to_child = task::spawn_listener {|po|
        server(po, to_parent);
    };
    let size = uint::from_str(args[1]);
    let workers = uint::from_str(args[2]);
    let start = std::time::precise_time_s();
    let to_child = to_child;
    let worker_results = [];
    uint::range(0u, workers) {|_i|
        let builder = task::mk_task_builder();
        worker_results += [task::future_result(builder)];
        task::run(builder) {||
            uint::range(0u, size / workers) {|_i|
                comm::send(to_child, bytes(100u));
            }
        };
    }
    vec::iter(worker_results) {|r| future::get(r); }
    comm::send(to_child, stop);
    let result = comm::recv(from_child);
    let end = std::time::precise_time_s();
    let elapsed = end - start;
    std::io::stdout().write_str(#fmt("Count is %?\n", result));
    std::io::stdout().write_str(#fmt("Test took %? seconds\n", elapsed));
    let thruput = ((size / workers * workers) as float) / (elapsed as float);
    std::io::stdout().write_str(#fmt("Throughput=%f per sec\n", thruput));
}

fn main(args: [str]) {
    let args1 = if vec::len(args) <= 1u { ["", "10000", "4"] } else { args };
    #debug("%?", args1);
    run(args1);
}

