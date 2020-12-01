(module
  (import "js" "put_i32" (func $put_i32 (param i32 i32)))
  (import "js" "set_time" (func $set_time (param i32)))
  (func $__wasi_fd_write (export "fd_write") (param i32 i32 i32 i32) (result i32)
    unreachable
  )
  (func $__wasi_fd_close (export "fd_close") (param i32) (result i32)
    unreachable
  )
  (func $__wasi_clock_time_get (export "clock_time_get") (param i32 i64 i32) (result i32)
    local.get 2
    call $set_time
    i32.const 0
  )
  (func $__wasi_proc_exit (export "proc_exit") (param i32)
    unreachable
  )
  (func $__wasi_environ_sizes_get (export "environ_sizes_get") (param i32 i32) (result i32)
    local.get 0
    i32.const 0
    call $put_i32
    local.get 1
    i32.const 0
    call $put_i32
    i32.const 0
  )
  (func $__wasi_environ_get (export "environ_get") (param i32 i32) (result i32)
    unreachable
  )
  (func $__wasi_fd_fdstat_get (export "fd_fdstat_get") (param i32 i32) (result i32)
    unreachable
  )
  (func $__wasi_path_open (export "path_open") (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)
    unreachable
  )
  (func $__wasi_fd_fdstat_set_flags (export "fd_fdstat_set_flags") (param i32 i32) (result i32)
    unreachable
  )
  (func $__wasi_fd_seek (export "fd_seek") (param i32 i64 i32 i32) (result i32)
    unreachable
  )
  (func $__wasi_fd_read (export "fd_read") (param i32 i32 i32 i32) (result i32)
    unreachable
  )
  (func $__wasi_fd_prestat_get (export "fd_prestat_get") (param i32 i32) (result i32)
    i32.const 8
  )
  (func $__wasi_fd_prestat_dir_name (export "fd_prestat_dir_name") (param i32 i32 i32) (result i32)
    i32.const 8
  )
)