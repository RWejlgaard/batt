; batt.asm - Battery monitoring tool in x86-64 assembly
; Linux only, direct syscalls, no libc.

%define SYS_read       0
%define SYS_write      1
%define SYS_open       2
%define SYS_close      3
%define SYS_ioctl      16
%define SYS_exit       60
%define SYS_getdents64 217

%define STDOUT 1
%define STDERR 2
%define TCGETS 0x5401
%define O_RDONLY_DIR 0x10000        ; O_RDONLY | O_DIRECTORY

%define BAR_WIDTH 20
%define MAX_BATS  8
%define NAME_MAX  32
%define DENTS_SZ  1024

%define ST_UNKNOWN     0
%define ST_CHARGING    1
%define ST_DISCHARGING 2
%define ST_FULL        3

section .rodata
    ; ANSI color codes
    red_color        db 27, '[31m', 0
    green_color      db 27, '[32m', 0
    yellow_color     db 27, '[33m', 0
    blue_color       db 27, '[34m', 0
    reset_color      db 27, '[0m', 0

    usage_msg        db 'Usage: batt [OPTIONS]', 10
                     db 'Show battery information', 10, 10
                     db 'Options:', 10
                     db '  -w, --watts       Show only wattage information', 10
                     db '  -p, --percentage  Show only percentage information', 10
                     db '  -t, --time        Show only time remaining information', 10
                     db '  -a, --amps        Show only amperage information', 10
                     db '  -h, --help        Show this help message', 10, 10
                     db 'Without any options, shows all battery information', 10
    usage_len        equ $ - usage_msg

    no_battery_msg   db 'No battery found', 10
    no_battery_len   equ $ - no_battery_msg

    unknown_opt_msg  db 'Unknown option: ', 0
    use_help_msg     db 10, 'Use -h or --help for usage information', 10, 0

    ; Command line options
    help_short       db '-h', 0
    help_long        db '--help', 0
    watts_short      db '-w', 0
    watts_long       db '--watts', 0
    percentage_short db '-p', 0
    percentage_long  db '--percentage', 0
    time_short       db '-t', 0
    time_long        db '--time', 0
    amps_short       db '-a', 0
    amps_long        db '--amps', 0

    ; sysfs
    supply_dir       db '/sys/class/power_supply/', 0
    a_capacity       db 'capacity', 0
    a_status         db 'status', 0
    a_current        db 'current_now', 0
    a_voltage        db 'voltage_now', 0
    a_power          db 'power_now', 0
    a_energy_now     db 'energy_now', 0
    a_energy_full    db 'energy_full', 0
    a_charge_now     db 'charge_now', 0
    a_charge_full    db 'charge_full', 0

    ; Status strings for comparison
    charging_str     db 'Charging', 0
    discharging_str  db 'Discharging', 0
    full_str         db 'Full', 0

    ; Time display strings
    full_in_str      db 'Full in', 0
    left_str         db 'Left', 0
    no_time_str      db '--:--', 0

section .bss
    ; Command line flags
    show_watts       resb 1
    show_percentage  resb 1
    show_time        resb 1
    show_amps        resb 1
    show_all         resb 1
    use_color        resb 1

    ; Battery discovery
    bat_names        resb MAX_BATS * NAME_MAX
    fallback_name    resb NAME_MAX
    bat_count        resq 1
    cur_name         resq 1
    dirfd            resq 1
    dents_len        resq 1
    dents_off        resq 1
    dirent_buf       resb DENTS_SZ

    ; Path building
    path_buf         resb 256
    bat_path_len     resq 1

    ; Battery data
    capacity         resq 1
    current_now      resq 1
    voltage_now      resq 1
    power_now        resq 1
    energy_now       resq 1
    energy_full      resq 1
    energy_based     resq 1     ; 1 if the battery reports energy_* rather than charge_*
    rate             resq 1
    time_mins        resq 1
    status_code      resq 1
    status_str       resb NAME_MAX

    ; Scratch
    num_buf          resb 40
    num_tmp          resb 32
    termios_buf      resb 64
    out_buf          resb 512

section .text
    global _start

; Compare argv entry in r10 against a short and a long option
%macro CHECKOPT 3
    mov rdi, r10
    mov rsi, %1
    call str_eq
    test al, al
    jnz %3
    mov rdi, r10
    mov rsi, %2
    call str_eq
    test al, al
    jnz %3
%endmacro

_start:
    mov byte [show_all], 1

    mov r12, [rsp]              ; argc
    lea r13, [rsp+8]            ; argv
    mov r14, 1

.arg_loop:
    cmp r14, r12
    jge .args_done
    mov r10, [r13 + r14*8]

    CHECKOPT help_short, help_long, show_help
    CHECKOPT watts_short, watts_long, .set_watts
    CHECKOPT percentage_short, percentage_long, .set_percentage
    CHECKOPT time_short, time_long, .set_time
    CHECKOPT amps_short, amps_long, .set_amps
    jmp unknown_option

.set_watts:
    mov byte [show_watts], 1
    jmp .flag_done
.set_percentage:
    mov byte [show_percentage], 1
    jmp .flag_done
.set_time:
    mov byte [show_time], 1
    jmp .flag_done
.set_amps:
    mov byte [show_amps], 1
.flag_done:
    mov byte [show_all], 0
    inc r14
    jmp .arg_loop

.args_done:
    call detect_tty
    call scan_batteries

    cmp qword [bat_count], 0
    je no_battery

    xor r15, r15
.bat_loop:
    cmp r15, [bat_count]
    jge .exit_ok

    mov rax, NAME_MAX
    mul r15
    lea rdi, [bat_names + rax]
    call set_bat_path
    call read_battery
    call render

    inc r15
    jmp .bat_loop

.exit_ok:
    xor edi, edi
    mov eax, SYS_exit
    syscall

show_help:
    mov eax, SYS_write
    mov edi, STDOUT
    mov rsi, usage_msg
    mov edx, usage_len
    syscall
    xor edi, edi
    mov eax, SYS_exit
    syscall

unknown_option:
    mov rbx, out_buf
    mov rsi, unknown_opt_msg
    call emit_str
    mov rsi, r10
    call emit_str
    mov rsi, use_help_msg
    call emit_str

    mov eax, SYS_write
    mov edi, STDERR
    mov rsi, out_buf
    mov rdx, rbx
    sub rdx, out_buf
    syscall

    mov edi, 1
    mov eax, SYS_exit
    syscall

no_battery:
    mov eax, SYS_write
    mov edi, STDOUT
    mov rsi, no_battery_msg
    mov edx, no_battery_len
    syscall
    mov edi, 1
    mov eax, SYS_exit
    syscall

; ---------------------------------------------------------------------------
; Battery discovery
; ---------------------------------------------------------------------------

; Collect every BAT* entry under /sys/class/power_supply into bat_names.
; If there are none, fall back to the first entry that exposes a capacity file.
scan_batteries:
    mov qword [bat_count], 0
    mov byte [fallback_name], 0

    mov eax, SYS_open
    mov rdi, supply_dir
    mov esi, O_RDONLY_DIR
    xor edx, edx
    syscall
    test eax, eax
    js .ret
    mov [dirfd], rax

.next_block:
    mov eax, SYS_getdents64
    mov rdi, [dirfd]
    mov rsi, dirent_buf
    mov edx, DENTS_SZ
    syscall
    test rax, rax
    jle .close
    mov [dents_len], rax
    mov qword [dents_off], 0

.entry:
    mov rax, [dents_off]
    cmp rax, [dents_len]
    jae .next_block

    lea rsi, [dirent_buf + rax]
    movzx edx, word [rsi + 16]      ; d_reclen
    add [dents_off], rdx
    lea rdi, [rsi + 19]             ; d_name
    mov [cur_name], rdi

    cmp byte [rdi], '.'
    je .entry

    cmp byte [rdi], 'B'
    jne .try_fallback
    cmp byte [rdi+1], 'A'
    jne .try_fallback
    cmp byte [rdi+2], 'T'
    jne .try_fallback

    call add_battery
    jmp .entry

.try_fallback:
    cmp byte [fallback_name], 0
    jne .entry

    mov rdi, [cur_name]
    call set_bat_path
    mov rdi, a_capacity
    call open_attr
    test eax, eax
    js .entry
    mov edi, eax
    mov eax, SYS_close
    syscall

    mov rdi, fallback_name
    mov rsi, [cur_name]
    call copy_name
    jmp .entry

.close:
    mov eax, SYS_close
    mov rdi, [dirfd]
    syscall

    cmp qword [bat_count], 0
    jne .ret
    cmp byte [fallback_name], 0
    je .ret
    mov rdi, bat_names
    mov rsi, fallback_name
    call copy_name
    mov qword [bat_count], 1
.ret:
    ret

; Append [cur_name] to the battery list
add_battery:
    mov rax, [bat_count]
    cmp rax, MAX_BATS
    jae .ret
    mov rcx, NAME_MAX
    mul rcx
    lea rdi, [bat_names + rax]
    mov rsi, [cur_name]
    call copy_name
    inc qword [bat_count]
.ret:
    ret

; rdi = dst, rsi = src, truncated to NAME_MAX
copy_name:
    mov ecx, NAME_MAX - 1
.copy:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .done
    inc rdi
    inc rsi
    dec ecx
    jnz .copy
    mov byte [rdi], 0
.done:
    ret

; rdi = battery name -> path_buf = "/sys/class/power_supply/<name>/"
set_bat_path:
    push rdi
    mov rdi, path_buf
    mov rsi, supply_dir
    call strcpy_z
    pop rsi
    call strcpy_z
    mov byte [rdi], '/'
    inc rdi
    mov byte [rdi], 0
    sub rdi, path_buf
    mov [bat_path_len], rdi
    ret

; ---------------------------------------------------------------------------
; sysfs attribute reads
; ---------------------------------------------------------------------------

; rdi = attribute name -> rax = fd (negative on error)
open_attr:
    mov rsi, rdi
    mov rdi, path_buf
    add rdi, [bat_path_len]
    call strcpy_z

    mov eax, SYS_open
    mov rdi, path_buf
    xor esi, esi                ; O_RDONLY
    xor edx, edx
    syscall
    ret

; rdi = attribute name -> rax = value, rdx = 1 if the file exists
read_attr_num:
    call open_attr
    test eax, eax
    js .missing

    mov r8d, eax
    xor eax, eax                ; SYS_read
    mov edi, r8d
    mov rsi, num_buf
    mov edx, 31
    syscall
    mov r9, rax

    mov eax, SYS_close
    mov edi, r8d
    syscall

    test r9, r9
    jle .missing
    mov byte [num_buf + r9], 0

    mov rdi, num_buf
    call atou
    mov edx, 1
    ret
.missing:
    xor eax, eax
    xor edx, edx
    ret

; Read the status file into status_str and classify it
read_status:
    mov qword [status_code], ST_UNKNOWN
    mov byte [status_str], 0

    mov rdi, a_status
    call open_attr
    test eax, eax
    js .ret

    mov r8d, eax
    xor eax, eax                ; SYS_read
    mov edi, r8d
    mov rsi, status_str
    mov edx, NAME_MAX - 1
    syscall
    mov r9, rax

    mov eax, SYS_close
    mov edi, r8d
    syscall

    test r9, r9
    jle .ret
    mov byte [status_str + r9], 0

    ; Trim the trailing newline (and any other control characters)
.trim:
    test r9, r9
    jz .classify
    dec r9
    cmp byte [status_str + r9], ' '
    ja .classify
    mov byte [status_str + r9], 0
    jmp .trim

.classify:
    mov rdi, status_str
    mov rsi, charging_str
    call str_eq
    test al, al
    jnz .charging

    mov rdi, status_str
    mov rsi, discharging_str
    call str_eq
    test al, al
    jnz .discharging

    mov rdi, status_str
    mov rsi, full_str
    call str_eq
    test al, al
    jz .ret
    mov qword [status_code], ST_FULL
    ret
.charging:
    mov qword [status_code], ST_CHARGING
    ret
.discharging:
    mov qword [status_code], ST_DISCHARGING
.ret:
    ret

; Read every metric for the battery currently in path_buf
read_battery:
    mov rdi, a_capacity
    call read_attr_num
    mov [capacity], rax

    call read_status

    mov rdi, a_current
    call read_attr_num
    mov [current_now], rax

    mov rdi, a_voltage
    call read_attr_num
    mov [voltage_now], rax

    mov rdi, a_power
    call read_attr_num
    mov [power_now], rax

    ; Energy-reporting batteries expose energy_*, charge-reporting ones charge_*
    mov rdi, a_energy_now
    call read_attr_num
    mov [energy_based], rdx
    test rdx, rdx
    jnz .have_now
    mov rdi, a_charge_now
    call read_attr_num
.have_now:
    mov [energy_now], rax

    cmp qword [energy_based], 0
    je .charge_full
    mov rdi, a_energy_full
    call read_attr_num
    jmp .have_full
.charge_full:
    mov rdi, a_charge_full
    call read_attr_num
.have_full:
    mov [energy_full], rax

    ; No power_now: derive it, µA * µV / 1e6 = µW
    cmp qword [power_now], 0
    jne .amps
    mov rax, [current_now]
    test rax, rax
    jz .amps
    mov rcx, [voltage_now]
    test rcx, rcx
    jz .amps
    mul rcx
    mov rcx, 1000000
    div rcx
    mov [power_now], rax

.amps:
    ; No current_now: derive it, µW * 1e6 / µV = µA
    cmp qword [current_now], 0
    jne calc_time
    mov rax, [power_now]
    test rax, rax
    jz calc_time
    mov rcx, [voltage_now]
    test rcx, rcx
    jz calc_time
    mov rsi, 1000000
    mul rsi
    div rcx
    mov [current_now], rax
    ; fall through

; Minutes until full (charging) or empty (discharging)
calc_time:
    mov qword [time_mins], 0

    mov rcx, [current_now]
    cmp qword [energy_based], 0
    je .have_rate
    mov rcx, [power_now]
.have_rate:
    mov [rate], rcx

    cmp qword [status_code], ST_CHARGING
    je .charging
    cmp qword [status_code], ST_DISCHARGING
    je .discharging
    ret

.charging:
    mov rax, [energy_full]
    sub rax, [energy_now]
    jbe .ret
    jmp .compute
.discharging:
    mov rax, [energy_now]
    test rax, rax
    jz .ret
.compute:
    mov rcx, [rate]
    cmp rcx, 1000
    jbe .ret
    mov rsi, 60
    mul rsi
    div rcx
    mov [time_mins], rax
.ret:
    ret

; ---------------------------------------------------------------------------
; Output
; ---------------------------------------------------------------------------

; Colors only make sense on a terminal
detect_tty:
    mov eax, SYS_ioctl
    mov edi, STDOUT
    mov esi, TCGETS
    mov rdx, termios_buf
    syscall
    test eax, eax
    jnz .ret
    mov byte [use_color], 1
.ret:
    ret

; Build the output for the current battery and write it in one syscall
render:
    mov rbx, out_buf

    cmp byte [show_all], 1
    je .all

    cmp byte [show_percentage], 1
    jne .no_pct
    call emit_percentage
    call emit_nl
.no_pct:
    cmp byte [show_watts], 1
    jne .no_watts
    call emit_watts
    call emit_nl
.no_watts:
    cmp byte [show_amps], 1
    jne .no_amps
    call emit_amps
    call emit_nl
.no_amps:
    cmp byte [show_time], 1
    jne .flush
    cmp qword [status_code], ST_CHARGING
    je .time
    cmp qword [status_code], ST_DISCHARGING
    jne .flush
.time:
    call emit_time
    call emit_nl
    jmp .flush

.all:
    ; BAT1 [####----------------]  50% - 5.23W 0.78A Left 02:30
    mov rax, NAME_MAX
    mul r15
    lea rsi, [bat_names + rax]
    call emit_str
    mov al, ' '
    call emit_char

    call emit_bar
    mov al, ' '
    call emit_char

    call emit_percentage
    mov al, ' '
    call emit_char

    call emit_status_symbol
    mov al, ' '
    call emit_char

    call emit_watts
    mov al, ' '
    call emit_char

    call emit_amps

    cmp qword [status_code], ST_CHARGING
    je .all_time
    cmp qword [status_code], ST_DISCHARGING
    jne .all_end
.all_time:
    mov al, ' '
    call emit_char
    call emit_time
.all_end:
    call emit_nl

.flush:
    mov rdx, rbx
    sub rdx, out_buf
    jz .ret
    mov eax, SYS_write
    mov edi, STDOUT
    mov rsi, out_buf
    syscall
.ret:
    ret

emit_bar:
    mov al, '['
    call emit_char

    mov rdi, [capacity]
    call battery_color
    mov rsi, rax
    call emit_color

    ; filled = capacity * BAR_WIDTH / 100, capped at BAR_WIDTH
    mov rax, [capacity]
    cmp rax, 100
    jbe .capped
    mov eax, 100
.capped:
    mov rcx, 100 / BAR_WIDTH
    xor edx, edx
    div rcx
    mov r8, rax                 ; filled
    mov rcx, rax

    mov al, '#'
.fill:
    test rcx, rcx
    jz .empty
    call emit_char
    dec rcx
    jmp .fill

.empty:
    mov rsi, reset_color
    call emit_color

    mov rcx, BAR_WIDTH
    sub rcx, r8                 ; empty

    mov al, '-'
.dash:
    test rcx, rcx
    jz .close
    call emit_char
    dec rcx
    jmp .dash

.close:
    mov al, ']'
    call emit_char
    ret

emit_percentage:
    mov rdi, [capacity]
    call battery_color
    mov rsi, rax
    call emit_color

    mov rax, [capacity]
    call emit_num_pad3
    mov al, '%'
    call emit_char

    mov rsi, reset_color
    call emit_color
    ret

emit_status_symbol:
    cmp qword [status_code], ST_CHARGING
    je .charging
    cmp qword [status_code], ST_DISCHARGING
    je .discharging
    cmp qword [status_code], ST_FULL
    je .full

    mov rsi, yellow_color
    call emit_color
    mov al, '?'
    jmp .emit
.charging:
    mov rsi, blue_color
    call emit_color
    mov al, '+'
    jmp .emit
.discharging:
    mov rdi, [capacity]
    call battery_color
    mov rsi, rax
    call emit_color
    mov al, '-'
    jmp .emit
.full:
    mov rsi, green_color
    call emit_color
    mov al, '='
.emit:
    call emit_char
    mov rsi, reset_color
    call emit_color
    ret

emit_watts:
    mov rax, [power_now]
    call emit_micro
    mov al, 'W'
    call emit_char
    ret

emit_amps:
    mov rax, [current_now]
    call emit_micro
    mov al, 'A'
    call emit_char
    ret

emit_time:
    cmp qword [status_code], ST_CHARGING
    jne .left
    mov rsi, full_in_str
    jmp .prefix
.left:
    mov rsi, left_str
.prefix:
    call emit_str
    mov al, ' '
    call emit_char

    mov rax, [time_mins]
    test rax, rax
    jnz .hhmm
    mov rsi, no_time_str
    jmp emit_str
.hhmm:
    mov rcx, 60
    xor edx, edx
    div rcx                     ; rax = hours, rdx = minutes
    push rdx
    call emit_num_pad2
    mov al, ':'
    call emit_char
    pop rax
    call emit_num_pad2
    ret

; rdi = percentage -> rax = color string
battery_color:
    mov rax, red_color
    cmp rdi, 10
    jbe .ret
    mov rax, yellow_color
    cmp rdi, 25
    jbe .ret
    mov rax, green_color
.ret:
    ret

; rax = value in micro-units -> "N.NN"
emit_micro:
    mov rcx, 1000000
    xor edx, edx
    div rcx
    push rdx
    call emit_num
    mov al, '.'
    call emit_char
    pop rax
    mov rcx, 10000
    xor edx, edx
    div rcx
    call emit_num_pad2
    ret

; ---------------------------------------------------------------------------
; Emit primitives - rbx is the output cursor, everything else is preserved
; ---------------------------------------------------------------------------

; al = character
emit_char:
    mov [rbx], al
    inc rbx
    ret

emit_nl:
    push rax
    mov al, 10
    call emit_char
    pop rax
    ret

; rsi = null-terminated string
emit_str:
    push rax
    push rsi
.loop:
    mov al, [rsi]
    test al, al
    jz .done
    mov [rbx], al
    inc rbx
    inc rsi
    jmp .loop
.done:
    pop rsi
    pop rax
    ret

; rsi = null-terminated string, emitted only when stdout is a terminal
emit_color:
    cmp byte [use_color], 0
    je .ret
    jmp emit_str
.ret:
    ret

; rax = value
emit_num:
    push rax
    push rcx
    push rdx
    push rsi

    mov rsi, num_tmp + 31
    mov byte [rsi], 0
    mov rcx, 10
.digit:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .digit
    call emit_str

    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

; rax = value, padded with a leading zero below 10
emit_num_pad2:
    push rax
    cmp rax, 10
    jae .num
    mov al, '0'
    call emit_char
.num:
    pop rax
    jmp emit_num

; rax = value, right-aligned in three columns
emit_num_pad3:
    push rax
    cmp rax, 100
    jae .num
    mov al, ' '
    call emit_char
    cmp qword [rsp], 10
    jae .num
    call emit_char
.num:
    pop rax
    jmp emit_num

; ---------------------------------------------------------------------------
; String helpers
; ---------------------------------------------------------------------------

; rdi = dst, rsi = src -> rdi points at the terminating null
strcpy_z:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .done
    inc rdi
    inc rsi
    jmp strcpy_z
.done:
    ret

; rdi = str1, rsi = str2 -> al = 1 when equal
str_eq:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne .differ
    test al, al
    jz .equal
    inc rdi
    inc rsi
    jmp str_eq
.equal:
    mov eax, 1
    ret
.differ:
    xor eax, eax
    ret

; rdi = null-terminated digits -> rax = value
atou:
    xor eax, eax
    xor ecx, ecx
.loop:
    mov cl, [rdi]
    sub cl, '0'
    cmp cl, 9
    ja .done
    lea rax, [rax + rax*4]      ; rax *= 5
    lea rax, [rcx + rax*2]      ; rax = rax*10 + digit
    inc rdi
    jmp .loop
.done:
    ret
