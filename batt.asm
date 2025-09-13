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
    show_all         resb 1

    ; Buffer for file operations
    file_buffer      resb 256
    temp_buffer      resb 64

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
    ; Read capacity
    mov rdi, capacity_file
    call read_number_from_file
    mov [capacity], rax

    ; Read current_now
    mov rdi, current_file
    call read_number_from_file
    mov [current_now], rax

    ; Read voltage_now
    mov rdi, voltage_file
    call read_number_from_file
    mov [voltage_now], rax

    ; Read charge_now
    mov rdi, charge_now_file
    call read_number_from_file
    mov [charge_now], rax

    ; Read charge_full
    mov rdi, charge_full_file
    call read_number_from_file
    mov [charge_full], rax

    ; Calculate power_now = current_now * voltage_now / 1000000
    mov rax, [current_now]
    mov rbx, [voltage_now]
    mul rbx             ; rax = current * voltage (in micro units)
    mov rbx, 1000000
    xor rdx, rdx
    div rbx             ; rax = power in microwatts
    mov [power_now], rax

    ; Read status string
    mov rdi, status_file
    call read_string_from_file

    ret

read_number_from_file:
    ; Input: rdi = filename
    ; Output: rax = number (0 if error)

    ; Open file
    mov rax, 2          ; sys_open
    mov rsi, 0          ; O_RDONLY
    mov rdx, 0          ; mode (not used for reading)
    syscall

    test rax, rax
    js read_error       ; Jump if negative (error)

    mov r8, rax         ; Save file descriptor

    ; Read file
    mov rax, 0          ; sys_read
    mov rdi, r8
    mov rsi, file_buffer
    mov rdx, 255
    syscall

    ; Close file
    push rax            ; Save bytes read
    mov rax, 3          ; sys_close
    mov rdi, r8
    syscall
    pop rcx             ; Restore bytes read (use rcx instead of rax)

    ; Null terminate the buffer
    mov byte [file_buffer + rcx], 0

    ; Convert to number
    mov rdi, file_buffer
    call ascii_to_number
    ret

read_error:
    xor rax, rax        ; Return 0 on error
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
    xor rax, rax        ; result = 0
    xor rbx, rbx        ; temp for digit

convert_loop:
    mov bl, [rdi]       ; Get next character
    test bl, bl         ; Check for null terminator
    jz convert_done

    ; Check if it's a digit
    cmp bl, '0'
    jb convert_done
    cmp bl, '9'
    ja convert_done

    ; Convert digit
    sub bl, '0'
    imul rax, 10        ; result *= 10
    add rax, rbx        ; result += digit

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

    ; Default: show all
    jmp display_all_info

display_all_info:
    ; Print battery name
    mov rsi, bat_name
    call print_string

    call display_progress_bar
    call print_space
    call print_space

    call display_percentage
    call print_space

    ; Display status symbol
    call display_status_symbol
    call print_space

    call display_watts
    call print_space

    call display_amps
    call print_space

    ; Display time remaining
    call display_time_remaining

    call print_newline
    ret

display_percentage_only:
    call display_percentage
    call print_newline
    ret

display_watts_only:
    call display_watts
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

    ; Calculate filled bars (capacity * 20 / 100)
    mov rax, [capacity]
    cmp rax, 100        ; Cap at 100%
    jle capacity_ok
    mov rax, 100
capacity_ok:
    mov rbx, 20
    mul rbx             ; rax = capacity * 20
    mov rbx, 100
    xor rdx, rdx
    div rbx             ; rax = filled bars

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
    ; Convert microwatts to watts with decimals
    mov rax, [power_now]
    mov rbx, 1000000
    xor rdx, rdx
    div rbx             ; rax = watts integer part

    push rdx            ; Save remainder for decimal part

    ; Print integer part
    mov rdi, rax
    call print_number

    ; Print decimal point
    mov rsi, dot_char
    call print_string

    ; Calculate and print decimal part (2 digits)
    pop rax             ; Get remainder
    mov rbx, 10000
    xor rdx, rdx
    div rbx             ; rax = first two decimal digits

    ; Print with leading zero if needed
    cmp rax, 10
    jge print_watts_decimal

    ; Print leading zero
    mov rdi, 0
    call print_number

print_watts_decimal:
    mov rdi, rax
    call print_number

    ; Print W
    mov rsi, w_char
    call print_string
    ret

display_amps:
    ; Convert microamps to amps with decimals
    mov rax, [current_now]
    mov rbx, 1000000
    xor rdx, rdx
    div rbx             ; rax = amps integer part

    push rdx            ; Save remainder for decimal part

    ; Print integer part
    mov rdi, rax
    call print_number

    ; Print decimal point
    mov rsi, dot_char
    call print_string

    ; Calculate and print decimal part (2 digits)
    pop rax             ; Get remainder
    mov rbx, 10000
    xor rdx, rdx
    div rbx             ; rax = first two decimal digits

    ; Print with leading zero if needed
    cmp rax, 10
    jge print_amps_decimal

    ; Print leading zero
    mov rdi, 0
    call print_number

print_amps_decimal:
    mov rdi, rax
    call print_number

    ; Print A
    mov rsi, a_char
    call print_string
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

print_string:
    ; Input: rsi = null-terminated string
    push rdi
    push rdx

    ; Calculate string length
    mov rdi, rsi
    call string_length
    mov rdx, rax        ; length in rdx

    ; Write to stdout
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    ; rsi already contains string address
    syscall

    pop rdx
    pop rdi
    ret

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