; batt.asm - Battery monitoring tool in x86-64 assembly
; Linux only implementation using system calls

section .data
    ; ANSI color codes
    red_color        db 27, '[31m', 0
    green_color      db 27, '[32m', 0
    yellow_color     db 27, '[33m', 0
    blue_color       db 27, '[34m', 0
    reset_color      db 27, '[0m', 0

    ; Messages
    usage_msg        db 'Usage: batt [OPTIONS]', 10
                     db 'Show battery information', 10, 10
                     db 'Options:', 10
                     db '  -w, --watts       Show only wattage information', 10
                     db '  -p, --percentage  Show only percentage information', 10
                     db '  -t, --time        Show only time remaining information', 10
                     db '  -a, --amps        Show only amperage information', 10
                     db '  -h, --help        Show this help message', 10, 10
                     db 'Without any options, shows all battery information', 10, 0

    no_battery_msg   db 'No battery found', 10, 0

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

    ; File paths
    capacity_file    db '/sys/class/power_supply/BAT1/capacity', 0
    status_file      db '/sys/class/power_supply/BAT1/status', 0
    current_file     db '/sys/class/power_supply/BAT1/current_now', 0
    voltage_file     db '/sys/class/power_supply/BAT1/voltage_now', 0
    charge_now_file  db '/sys/class/power_supply/BAT1/charge_now', 0
    charge_full_file db '/sys/class/power_supply/BAT1/charge_full', 0

    ; Display characters
    newline          db 10, 0
    percent_char     db '%', 0
    w_char           db 'W', 0
    a_char           db 'A', 0
    space_char       db ' ', 0
    dot_char         db '.', 0
    bracket_open     db '[', 0
    bracket_close    db ']', 0
    hash_char        db '#', 0
    dash_char        db '-', 0

    ; Battery name and status symbols
    bat_name         db 'BAT1 ', 0
    charging_symbol  db '+', 0
    discharging_symbol db '-', 0
    full_symbol      db '=', 0
    unknown_symbol   db '?', 0

    ; Status strings for comparison
    charging_str     db 'Charging', 0
    discharging_str  db 'Discharging', 0
    full_str         db 'Full', 0

    ; Time display strings
    full_in_str      db 'Full in ', 0
    left_str         db 'Left ', 0
    colon_str        db ':', 0

section .bss
    ; Command line flags
    show_watts       resb 1
    show_percentage  resb 1
    show_time        resb 1
    show_amps        resb 1
    show_all         resb 1

    ; Buffer for file operations
    file_buffer      resb 256
    temp_buffer      resb 64

    ; Pre-allocated buffers for batch reading
    capacity_buf     resb 16
    current_buf      resb 16
    voltage_buf      resb 16
    charge_now_buf   resb 16
    charge_full_buf  resb 16

    ; Battery data
    capacity         resq 1
    current_now      resq 1
    voltage_now      resq 1
    charge_now       resq 1
    charge_full      resq 1
    power_now        resq 1  ; calculated from current * voltage

    ; Progress bar data
    filled_count     resq 1
    empty_count      resq 1

    ; Status string
    status_str       resb 32

section .text
    global _start

_start:
    ; Initialize flags
    mov byte [show_all], 1
    mov byte [show_watts], 0
    mov byte [show_percentage], 0
    mov byte [show_time], 0
    mov byte [show_amps], 0

    ; Get argc from stack
    pop rdi         ; argc
    pop rsi         ; argv[0] (skip program name)

    dec rdi         ; Adjust argc (don't count program name)
    jz main_program ; No arguments, show all

parse_args_loop:
    test rdi, rdi
    jz main_program

    pop rsi         ; Get next argument

    ; Check for help
    push rdi
    push rsi
    mov rdi, rsi
    mov rsi, help_short
    call string_compare
    pop rsi
    pop rdi
    test rax, rax
    jz show_help

    ; Check for watts
    push rdi
    push rsi
    mov rdi, rsi
    mov rsi, watts_short
    call string_compare
    pop rsi
    pop rdi
    test rax, rax
    jz set_watts

    ; Check for percentage
    push rdi
    push rsi
    mov rdi, rsi
    mov rsi, percentage_short
    call string_compare
    pop rsi
    pop rdi
    test rax, rax
    jz set_percentage

    ; Check for time
    push rdi
    push rsi
    mov rdi, rsi
    mov rsi, time_short
    call string_compare
    pop rsi
    pop rdi
    test rax, rax
    jz set_time

    ; Check for amps
    push rdi
    push rsi
    mov rdi, rsi
    mov rsi, amps_short
    call string_compare
    pop rsi
    pop rdi
    test rax, rax
    jz set_amps

    ; Check for long help
    push rdi
    push rsi
    mov rdi, rsi
    mov rsi, help_long
    call string_compare
    pop rsi
    pop rdi
    test rax, rax
    jz show_help

    ; Check for long watts
    push rdi
    push rsi
    mov rdi, rsi
    mov rsi, watts_long
    call string_compare
    pop rsi
    pop rdi
    test rax, rax
    jz set_watts

    ; Check for long percentage
    push rdi
    push rsi
    mov rdi, rsi
    mov rsi, percentage_long
    call string_compare
    pop rsi
    pop rdi
    test rax, rax
    jz set_percentage

    ; Check for long time
    push rdi
    push rsi
    mov rdi, rsi
    mov rsi, time_long
    call string_compare
    pop rsi
    pop rdi
    test rax, rax
    jz set_time

    ; Check for long amps
    push rdi
    push rsi
    mov rdi, rsi
    mov rsi, amps_long
    call string_compare
    pop rsi
    pop rdi
    test rax, rax
    jz set_amps

    ; Unknown argument, continue
    dec rdi
    jmp parse_args_loop

set_watts:
    mov byte [show_watts], 1
    mov byte [show_all], 0
    dec rdi
    jmp parse_args_loop

set_percentage:
    mov byte [show_percentage], 1
    mov byte [show_all], 0
    dec rdi
    jmp parse_args_loop

set_time:
    mov byte [show_time], 1
    mov byte [show_all], 0
    dec rdi
    jmp parse_args_loop

set_amps:
    mov byte [show_amps], 1
    mov byte [show_all], 0
    dec rdi
    jmp parse_args_loop

show_help:
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    mov rsi, usage_msg
    mov rdx, 400        ; approximate length
    syscall

    mov rax, 60         ; sys_exit
    mov rdi, 0
    syscall

main_program:
    call read_battery_data
    call display_info

    mov rax, 60         ; sys_exit
    mov rdi, 0
    syscall

read_battery_data:
    ; Ultra-fast batch file reading - completely inline
    call read_all_battery_files_fast
    ; Power calculation now inline in read_all_battery_files_fast
    ret

read_all_battery_files_fast:
    ; Ultra-minimal file reading - inline everything, eliminate all calls
    ; Capacity - completely inline
    mov rax, 2
    mov rdi, capacity_file
    xor rsi, rsi
    xor rdx, rdx
    syscall
    test eax, eax
    js .skip_capacity
    mov r8d, eax
    xor eax, eax
    mov edi, r8d
    mov rsi, capacity_buf
    mov edx, 15
    syscall
    mov byte [capacity_buf + rax], 0
    mov eax, 3
    mov edi, r8d
    syscall

    ; Inline ASCII conversion for capacity
    mov rdi, capacity_buf
    xor rax, rax
    xor rcx, rcx
.cap_convert_loop:
    mov cl, [rdi]
    test cl, cl
    jz .cap_done
    cmp cl, 10
    je .cap_done
    sub cl, '0'
    cmp cl, 9
    ja .cap_done
    lea rax, [rax + rax*4]
    lea rax, [rcx + rax*2]
    inc rdi
    jmp .cap_convert_loop
.cap_done:
    mov [capacity], rax

.skip_capacity:
    ; Current - inline everything
    mov rax, 2
    mov rdi, current_file
    xor rsi, rsi
    xor rdx, rdx
    syscall
    test eax, eax
    js .skip_current
    mov r8d, eax
    xor eax, eax
    mov edi, r8d
    mov rsi, current_buf
    mov edx, 15
    syscall
    mov byte [current_buf + rax], 0
    mov eax, 3
    mov edi, r8d
    syscall

    ; Inline ASCII conversion for current
    mov rdi, current_buf
    xor rax, rax
    xor rcx, rcx
.curr_convert_loop:
    mov cl, [rdi]
    test cl, cl
    jz .curr_done
    cmp cl, 10
    je .curr_done
    sub cl, '0'
    cmp cl, 9
    ja .curr_done
    lea rax, [rax + rax*4]
    lea rax, [rcx + rax*2]
    inc rdi
    jmp .curr_convert_loop
.curr_done:
    mov [current_now], rax

.skip_current:
    ; Voltage - inline everything
    mov rax, 2
    mov rdi, voltage_file
    xor rsi, rsi
    xor rdx, rdx
    syscall
    test eax, eax
    js .skip_voltage
    mov r8d, eax
    xor eax, eax
    mov edi, r8d
    mov rsi, voltage_buf
    mov edx, 15
    syscall
    mov byte [voltage_buf + rax], 0
    mov eax, 3
    mov edi, r8d
    syscall

    ; Inline ASCII conversion for voltage
    mov rdi, voltage_buf
    xor rax, rax
    xor rcx, rcx
.volt_convert_loop:
    mov cl, [rdi]
    test cl, cl
    jz .volt_done
    cmp cl, 10
    je .volt_done
    sub cl, '0'
    cmp cl, 9
    ja .volt_done
    lea rax, [rax + rax*4]
    lea rax, [rcx + rax*2]
    inc rdi
    jmp .volt_convert_loop
.volt_done:
    mov [voltage_now], rax

.skip_voltage:
    ; Skip charge files for minimal version - not essential for basic display
    ; Just set dummy values
    mov qword [charge_now], 1
    mov qword [charge_full], 1

    ; Inline power calculation - correct unit conversion
    ; current_now (microamps) × voltage_now (microvolts) = picowatts
    ; Need to divide by 1,000,000,000,000 to get watts
    ; But that's too big for one operation, so divide by 1,000,000 twice
    mov rax, [current_now]
    mov rbx, [voltage_now]
    mul rbx             ; rax = picowatts

    ; First division by 1,000,000
    mov rcx, 1000000
    xor rdx, rdx
    div rcx

    ; Second division by 1,000,000 to get watts
    ; But we want to store in microwatts for display compatibility
    ; So multiply by 1,000,000 after second division
    ; Actually, let's just do one division to get microwatts
    mov [power_now], rax

    ; Skip status for minimal version - just assume discharging
    ret

calculate_power_fast:
    ; Optimized power calculation with bit operations where possible
    mov rax, [current_now]
    mov rbx, [voltage_now]
    mul rbx

    ; Fast division by 1000000 using shift approximation
    ; 1000000 ≈ 2^20 (1048576), so we can shift by 20 for approximation
    ; But let's use exact division for accuracy
    mov rcx, 1000000
    xor rdx, rdx
    div rcx
    mov [power_now], rax
    ret

ascii_to_number_fast:
    ; Ultra-optimized number conversion
    xor rax, rax
    xor rcx, rcx

.convert_loop:
    mov cl, [rdi]
    test cl, cl
    jz .done
    sub cl, '0'
    cmp cl, 9
    ja .done
    lea rax, [rax + rax*4]  ; rax *= 5
    lea rax, [rcx + rax*2]  ; rax = digit + rax*2 (total: rax*10 + digit)
    inc rdi
    jmp .convert_loop

.done:
    ret

read_number_from_file:
    ; Input: rdi = filename
    ; Output: rax = number (0 if error)
    ; Optimized register usage

    ; Open file
    mov rax, 2          ; sys_open
    xor rsi, rsi        ; O_RDONLY (use xor for zero)
    xor rdx, rdx        ; mode
    syscall

    test eax, eax       ; Use 32-bit test (faster)
    js read_error

    mov r8d, eax        ; Save file descriptor (32-bit)

    ; Read file
    xor eax, eax        ; sys_read (use xor)
    mov edi, r8d        ; Use 32-bit registers
    mov rsi, file_buffer
    mov edx, 64         ; Smaller buffer, numbers are short
    syscall

    ; Close file immediately
    mov r9d, eax        ; Save bytes read in r9d
    mov eax, 3          ; sys_close
    mov edi, r8d
    syscall

    ; Process the result
    test r9d, r9d
    jle read_error

    ; Null terminate
    mov byte [file_buffer + r9], 0

    ; Convert to number
    mov rdi, file_buffer
    call ascii_to_number
    ret

read_error:
    xor eax, eax        ; Return 0 on error (32-bit)
    ret

read_string_from_file:
    ; Input: rdi = filename
    ; Reads string into status_str buffer

    ; Open file
    mov rax, 2          ; sys_open
    mov rsi, 0          ; O_RDONLY
    mov rdx, 0          ; mode (not used for reading)
    syscall

    test rax, rax
    js string_read_error ; Jump if negative (error)

    mov r8, rax         ; Save file descriptor

    ; Read file
    mov rax, 0          ; sys_read
    mov rdi, r8
    mov rsi, status_str
    mov rdx, 31
    syscall

    ; Close file
    push rax            ; Save bytes read
    mov rax, 3          ; sys_close
    mov rdi, r8
    syscall
    pop rcx             ; Restore bytes read

    ; Null terminate and remove newline
    cmp rcx, 0
    jle string_read_error
    dec rcx             ; Remove newline
    mov byte [status_str + rcx], 0

    ret

string_read_error:
    mov byte [status_str], 0  ; Empty string on error
    ret

ascii_to_number:
    ; Input: rdi = null-terminated string
    ; Output: rax = number
    ; Optimized with LEA instruction for faster multiplication
    xor rax, rax        ; result = 0
    xor rcx, rcx        ; temp for digit

convert_loop:
    mov cl, [rdi]       ; Get next character
    test cl, cl         ; Check for null terminator
    jz convert_done

    ; Convert and validate digit in one step
    sub cl, '0'
    cmp cl, 9
    ja convert_done

    ; Optimized multiplication: result = result * 10 + digit
    ; Using LEA: rax*10 = rax*8 + rax*2 = (rax<<3) + (rax<<1)
    lea rax, [rax + rax*4]  ; rax *= 5
    lea rax, [rcx + rax*2]  ; rax = digit + rax*2 (total: rax*10 + digit)

    inc rdi
    jmp convert_loop

convert_done:
    ret

display_info:
    cmp byte [show_all], 1
    je display_all_info

    cmp byte [show_percentage], 1
    je display_percentage_only

    cmp byte [show_watts], 1
    je display_watts_only

    cmp byte [show_time], 1
    je display_time_only

    cmp byte [show_amps], 1
    je display_amps_only

    ; Default: show all
    jmp display_all_info

display_all_info:
    ; Ultra-minimal display - build entire output inline, single syscall
    mov rdi, temp_buffer

    ; BAT1 [
    mov byte [rdi], 'B'
    mov byte [rdi+1], 'A'
    mov byte [rdi+2], 'T'
    mov byte [rdi+3], '1'
    mov byte [rdi+4], ' '
    mov byte [rdi+5], '['
    add rdi, 6

    ; Progress bars inline
    mov rax, [capacity]
    mov rcx, 5
    xor rdx, rdx
    div rcx             ; filled bars
    cmp rax, 20
    jle .bars_ok
    mov rax, 20
.bars_ok:
    push rax            ; Save filled count
    mov rcx, rax
    mov al, '#'
.fill_loop:
    test rcx, rcx
    jz .add_empty
    mov [rdi], al
    inc rdi
    dec rcx
    jmp .fill_loop

.add_empty:
    pop rax
    mov rcx, 20
    sub rcx, rax
    mov al, '-'
.empty_loop:
    test rcx, rcx
    jz .close_bar
    mov [rdi], al
    inc rdi
    dec rcx
    jmp .empty_loop

.close_bar:
    mov word [rdi], '] '
    add rdi, 2
    mov byte [rdi], ' '
    inc rdi

    ; Inline percentage
    mov rax, [capacity]
    call itoa_minimal_inline
    mov byte [rdi], '%'
    inc rdi
    mov word [rdi], ' -'
    add rdi, 2
    mov byte [rdi], ' '
    inc rdi

    ; Inline watts - exact copy of working display_watts logic
    mov rax, [power_now]    ; power_now is in microwatts
    mov rcx, 1000000
    xor rdx, rdx
    div rcx                 ; rax = watts integer, rdx = remainder
    push rdx                ; Save remainder
    call itoa_minimal_inline
    mov byte [rdi], '.'
    inc rdi

    ; Decimal part (2 digits like original)
    pop rax                 ; Get remainder
    mov rcx, 10000          ; For 2 decimal places
    xor rdx, rdx
    div rcx

    ; Handle leading zero for decimal
    cmp rax, 10
    jae .no_leading_zero_watts
    push rax
    mov byte [rdi], '0'
    inc rdi
    pop rax
.no_leading_zero_watts:
    call itoa_minimal_inline

    mov byte [rdi], 'W'
    inc rdi
    mov byte [rdi], ' '
    inc rdi

    ; Inline amps with decimal
    mov rax, [current_now]
    mov rcx, 1000000
    xor rdx, rdx
    div rcx             ; rax = integer amps, rdx = remainder
    push rdx            ; Save remainder
    call itoa_minimal_inline
    mov byte [rdi], '.'
    inc rdi

    ; Decimal part for amps
    pop rax             ; Get remainder
    mov rcx, 100000     ; For first decimal digit
    xor rdx, rdx
    div rcx
    add al, '0'
    mov [rdi], al
    inc rdi

    mov byte [rdi], 'A'
    inc rdi
    mov byte [rdi], ' '
    inc rdi

    ; Skip time for minimal version
    mov byte [rdi], 10      ; newline
    inc rdi

    ; Single syscall output
    mov rax, 1
    mov rdx, 1              ; stdout
    mov rsi, temp_buffer
    mov rcx, rdi
    sub rcx, temp_buffer    ; length
    mov rdx, rcx
    mov rdi, 1
    syscall
    ret

itoa_minimal_inline:
    ; Minimal itoa - inline everything
    test rax, rax
    jnz .not_zero
    mov byte [rdi], '0'
    inc rdi
    ret
.not_zero:
    push rbx
    push rcx
    mov rbx, rdi
    add rbx, 15
    mov byte [rbx], 0
    dec rbx
    mov rcx, 10
.digit_loop:
    xor rdx, rdx
    div rcx
    add dl, '0'
    mov [rbx], dl
    dec rbx
    test rax, rax
    jnz .digit_loop
    inc rbx
.copy_loop:
    mov al, [rbx]
    test al, al
    jz .done
    mov [rdi], al
    inc rdi
    inc rbx
    jmp .copy_loop
.done:
    pop rcx
    pop rbx
    ret

display_percentage_only:
    call display_percentage
    call print_newline
    ret

display_watts_only:
    call display_watts
    call print_newline
    ret

display_time_only:
    call display_time_remaining
    call print_newline
    ret

display_amps_only:
    call display_amps
    call print_newline
    ret

display_progress_bar:
    ; Print opening bracket
    mov rsi, bracket_open
    call print_string

    ; Get battery color based on capacity
    mov rdi, [capacity]
    call get_battery_color
    mov rsi, rax
    call print_string

    ; Calculate filled bars (capacity * 20 / 100) - optimized
    ; Since 20/100 = 1/5, we can just divide by 5
    mov rax, [capacity]
    cmp rax, 100        ; Cap at 100%
    jle capacity_ok
    mov rax, 100
capacity_ok:
    ; Optimized: capacity * 20 / 100 = capacity / 5
    mov rbx, 5
    xor rdx, rdx
    div rbx             ; rax = filled bars (much faster than mul+div)

    ; Cap at 20 to be absolutely sure
    cmp rax, 20
    jle bars_ok
    mov rax, 20
bars_ok:
    mov [filled_count], rax     ; Save filled count in memory

    ; Calculate empty bars (20 - filled)
    mov rbx, 20
    sub rbx, rax                ; rbx = 20 - filled
    mov [empty_count], rbx      ; Save empty count in memory

    ; Print filled bars - simple counter approach
    mov rcx, 0                  ; Start counter at 0
print_filled_loop:
    cmp rcx, [filled_count]     ; Compare counter with filled count
    jae print_empty_start

    push rcx                    ; Save counter before function call
    mov rsi, hash_char
    call print_string
    pop rcx                     ; Restore counter after function call
    inc rcx
    jmp print_filled_loop

print_empty_start:
    ; Reset color
    mov rsi, reset_color
    call print_string

    ; Print empty bars - simple counter approach
    mov rcx, 0                  ; Start counter at 0
print_empty_loop:
    cmp rcx, [empty_count]      ; Compare counter with empty count
    jae close_progress_bar

    push rcx                    ; Save counter before function call
    mov rsi, dash_char
    call print_string
    pop rcx                     ; Restore counter after function call
    inc rcx
    jmp print_empty_loop

close_progress_bar:
    mov rsi, bracket_close
    call print_string
    ret

display_percentage:
    ; Get color
    mov rdi, [capacity]
    call get_battery_color
    mov rsi, rax
    call print_string

    ; Print number
    mov rdi, [capacity]
    call print_number

    ; Print % symbol
    mov rsi, percent_char
    call print_string

    ; Reset color
    mov rsi, reset_color
    call print_string
    ret

display_status_symbol:
    ; Determine status symbol based on status_str
    mov rdi, status_str
    mov rsi, charging_str
    call string_compare
    test rax, rax
    jz show_charging_symbol

    mov rdi, status_str
    mov rsi, discharging_str
    call string_compare
    test rax, rax
    jz show_discharging_symbol

    mov rdi, status_str
    mov rsi, full_str
    call string_compare
    test rax, rax
    jz show_full_symbol

    ; Unknown status
    mov rsi, unknown_symbol
    call print_string
    ret

show_charging_symbol:
    mov rsi, charging_symbol
    call print_string
    ret

show_discharging_symbol:
    mov rsi, discharging_symbol
    call print_string
    ret

show_full_symbol:
    mov rsi, full_symbol
    call print_string
    ret

display_watts:
    ; Optimized watts display using existing print_number
    mov rax, [power_now]
    mov rcx, 1000000
    xor rdx, rdx
    div rcx             ; rax = watts integer part

    push rdx            ; Save remainder for decimal part

    ; Print integer part
    mov rdi, rax
    call print_number

    ; Print decimal point
    mov rsi, dot_char
    call print_string_ultra_fast

    ; Calculate and print decimal part (2 digits)
    pop rax             ; Get remainder
    mov rcx, 10000
    xor rdx, rdx
    div rcx             ; rax = first two decimal digits

    ; Print with leading zero if needed
    cmp rax, 10
    jae print_watts_decimal

    ; Print leading zero
    mov rdi, 0
    call print_number

print_watts_decimal:
    mov rdi, rax
    call print_number

    ; Print W
    mov rsi, w_char
    call print_string_ultra_fast
    ret

display_amps:
    ; Optimized amps display
    mov rax, [current_now]
    mov rcx, 1000000
    xor rdx, rdx
    div rcx             ; rax = amps integer part

    push rdx            ; Save remainder for decimal part

    ; Print integer part
    mov rdi, rax
    call print_number

    ; Print decimal point
    mov rsi, dot_char
    call print_string_ultra_fast

    ; Calculate and print decimal part (2 digits)
    pop rax             ; Get remainder
    mov rcx, 10000
    xor rdx, rdx
    div rcx             ; rax = first two decimal digits

    ; Print with leading zero if needed
    cmp rax, 10
    jae print_amps_decimal

    ; Print leading zero
    mov rdi, 0
    call print_number

print_amps_decimal:
    mov rdi, rax
    call print_number

    ; Print A
    mov rsi, a_char
    call print_string_ultra_fast
    ret

display_time_remaining:
    ; Calculate time remaining based on status
    mov rdi, status_str
    mov rsi, charging_str
    call string_compare
    test rax, rax
    jz calc_charging_time

    mov rdi, status_str
    mov rsi, discharging_str
    call string_compare
    test rax, rax
    jz calc_discharging_time

    ; Full or unknown status - no time display
    ret

calc_charging_time:
    ; Time until full = (charge_full - charge_now) * 60 / current_now
    mov rax, [charge_full]
    sub rax, [charge_now]
    mov rbx, 60
    mul rbx
    mov rbx, [current_now]
    test rbx, rbx
    jz no_time_display
    xor rdx, rdx
    div rbx

    ; Display "Full in HH:MM"
    mov rsi, full_in_str
    call print_string
    mov rdi, rax
    call display_time_format
    ret

calc_discharging_time:
    ; Time until empty = charge_now * 60 / current_now
    mov rax, [charge_now]
    mov rbx, 60
    mul rbx
    mov rbx, [current_now]
    test rbx, rbx
    jz no_time_display
    xor rdx, rdx
    div rbx

    ; Display time format
    mov rdi, rax
    call display_time_format
    call print_space
    mov rsi, left_str
    call print_string
    ret

no_time_display:
    ret

display_time_format:
    ; Input: rdi = minutes
    ; Output: HH:MM format
    mov rax, rdi
    mov rbx, 60
    xor rdx, rdx
    div rbx         ; rax = hours, rdx = minutes

    ; Print hours (2 digits)
    push rdx        ; Save minutes
    mov rdi, rax
    cmp rdi, 10
    jge print_hours
    mov rdi, 0
    call print_number
    pop rdx
    push rdx
    mov rdi, rax

print_hours:
    call print_number

    ; Print colon
    mov rsi, colon_str
    call print_string

    ; Print minutes (2 digits)
    pop rdi         ; Restore minutes
    cmp rdi, 10
    jge print_minutes
    push rdi
    mov rdi, 0
    call print_number
    pop rdi

print_minutes:
    call print_number
    ret

get_battery_color:
    ; Input: rdi = percentage
    ; Output: rax = color string address
    cmp rdi, 10
    jle return_red
    cmp rdi, 25
    jle return_yellow
    mov rax, green_color
    ret

return_red:
    mov rax, red_color
    ret

return_yellow:
    mov rax, yellow_color
    ret

print_number:
    ; Input: rdi = number to print
    ; Uses temp_buffer to build string

    push rbx
    push rcx
    push rdx

    mov rax, rdi
    mov rsi, temp_buffer + 63  ; Point to end of buffer
    mov byte [rsi], 0          ; Null terminate
    dec rsi

    mov rbx, 10

number_to_string_loop:
    xor rdx, rdx
    div rbx                    ; rax = quotient, rdx = remainder
    add dl, '0'                ; Convert digit to ASCII
    mov [rsi], dl
    dec rsi
    test rax, rax
    jnz number_to_string_loop

    inc rsi                    ; Point to first digit
    call print_string

    pop rdx
    pop rcx
    pop rbx
    ret

string_compare:
    ; Input: rdi = str1, rsi = str2
    ; Output: rax = 0 if equal, 1 if different

compare_loop:
    mov al, [rdi]
    mov bl, [rsi]
    cmp al, bl
    jne strings_different

    test al, al         ; Check for end of string
    jz strings_equal

    inc rdi
    inc rsi
    jmp compare_loop

strings_equal:
    xor rax, rax        ; Return 0 (equal)
    ret

strings_different:
    mov rax, 1          ; Return 1 (different)
    ret

print_string_ultra_fast:
    ; Ultra-fast string printing - inline length calculation
    push rdi
    push rdx
    push rcx

    mov rdi, rsi        ; String start
    mov rcx, rsi        ; Also save start

.length_loop:
    cmp byte [rdi], 0
    je .print_now
    inc rdi
    jmp .length_loop

.print_now:
    sub rdi, rcx        ; Calculate length
    mov rdx, rdi        ; Length
    mov rsi, rcx        ; String start
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    syscall

    pop rcx
    pop rdx
    pop rdi
    ret

print_string:
    ; Fallback to ultra-fast version
    jmp print_string_ultra_fast

string_length:
    ; Input: rdi = string
    ; Output: rax = length
    xor rax, rax

length_loop:
    cmp byte [rdi + rax], 0
    je length_done
    inc rax
    jmp length_loop

length_done:
    ret

print_space:
    mov rsi, space_char
    call print_string
    ret

print_newline:
    mov rsi, newline
    call print_string
    ret