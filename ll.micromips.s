#  linux_logo in micromips (mips16e2) assembler 0.49
#
#  By
#       Vince Weaver <vince _at_ deater.net>
#
#  assemble with     "as -mmicromips -o ll.micromips.o ll.micromips.s"
#  link with         "ld -o ll_micromips ll.micromips.o"

#.nan    legacy

.include "logo.include"

# Difference from mips16
#	+ andi/ori/xori
#	+ cache
#	+ ext -- extract bitfield
#	+ ins -- insert bitfield
#	+ loads can be GP relative
#	+ lui -- load upper immediate
#	+ ll/sc/pause
#	+ move conditional
#	+ prefetch
# + Removal of all non-MIPS32 instructions (bt/cmp/save/restore)?


#
# MIPS16e2
#
# Can do 64-bit ops on 64-bit procs
#  Has 8 registers:
#	0,1,2,3,4,5,6,7 correpsond to MIPS32 16,17,2,3,4,5,6,7
#	don't use 0-7 though, use $16,$17,$2 etc
# MIPS32 reg 24 is used as a condition code register
# MIPS32 reg 29 is SP and 31 is RA
#   mips16 mov instruction can access all registers
# JALX, JR, JALR, JALRC and JRC can switch between 16/32 mode
# PC relative addressing is added for lw and addi
# an instruction can be "extended" to have up to a 16-bit immediate

# Instructions (64-bit instructions only avail on 64-bit CPU)
# + load instructions : lb/lbu/ld/lh/lhu/lw/lwu
#   * lb ry, offset(rx)  -- offset=5bits (extnd to 16-bits)
#   * lw can also be SP or PC relative
# + store instructions: sb/sd/sh/sw
#
# "Extended" instructions allow making immediate field larger,
#    for a 32-bit instruction
#    cannot be in branch delay slots

#
# Optimization:
#  LZSS:
#	+ 118 bytes -- original port of mips16 code
#

#
# Overall:
#	+ 1396 bytes -- original port of mips16 code

#
# ASSEMBLER ANNOYANCES:

#
# Keep gas from handling branch-delay and load-delay slots automatically
#

#.set noreorder

#
# Register definitions.  Older gas could only hand numerical
#                        16 17  2  3  4  5  6  7
# On MIPS16 you only get s0,s1,v0,v1,a0,a1,a2,a3

# Traditional MIPS register values
# zero  = 0
# at    = 1     # Assembler Temporary
# v0-v1 = 2-3   # Returned value registers
# a0-a3 = 4-7   # Argument Registers (Caller Saved)
# t0-t7 = 8-15  # Temporary (Caller Saved)
# s0-s7 = 16-23 # Callee-Saved
# t8-t9 = 24-25
# k0-k1 = 26-27 # Kernel Reserved (do not use!)
# gp    = 28    # Global Pointer
# sp    = 29    # Stack Pointer
# fp    = 30    # Frame Pointer (GCC)
# s8    = 30    # s8 on mips compiler
# ra    = 31    # return address (of subroutine call)


# offsets into the results returned by the uname syscall
.equ U_SYSNAME,0
.equ U_NODENAME,65
.equ U_RELEASE,65*2
.equ U_VERSION,(65*3)
.equ U_MACHINE,(65*4)
.equ U_DOMAINNAME,65*5

# offset into the results returned by the sysinfo syscall
.equ S_TOTALRAM,16

# Sycscalls
#  -- the lower syscalls are compat with IRIX, etc
#     syscalls trash r14?
#  -- no branch delay after syscall

.equ SYSCALL_LINUX,	4000
.equ SYSCALL_EXIT,      SYSCALL_LINUX+1
.equ SYSCALL_READ,      SYSCALL_LINUX+3
.equ SYSCALL_WRITE,     SYSCALL_LINUX+4
.equ SYSCALL_OPEN,      SYSCALL_LINUX+5
.equ SYSCALL_CLOSE,     SYSCALL_LINUX+6
.equ SYSCALL_SYSINFO,   SYSCALL_LINUX+116
.equ SYSCALL_UNAME,     SYSCALL_LINUX+122
.equ SYSCALL_SYNC,	SYSCALL_LINUX+36

#
.equ STDIN, 0
.equ STDOUT,1
.equ STDERR,2



	.globl __start

__start:

	#=========================
	# PRINT LOGO
	#=========================

# LZSS decompression algorithm implementation
# by Stephan Walter 2002, based on LZSS.C by Haruhiko Okumura 1989
# optimized some more by Vince Weaver

	lw	$s0,out_buffer_addr
	la	$s1,logo

	li      $a2,(N-F)   	     	# R



decompression_loop:

	lbu	$v0,0($s1)	# load in a byte
	addiu	$s1,$s1,1	# increment source pointer

	li	$a3,0xff00	# 32-bit, zero extended
	or	$v0,$a3		# put 0xff in top as a hackish 8-bit counter

test_flags:
	la	$a3, logo_end
					# have we reached the end?
	beq	$s1,$a3,done_logo	# if so, exit

	li	$a3,1
	and     $a3,$v0		# test to see if discrete char

	srl	$v0,$v0,1	# shift

	bnez	$a3,discrete_char
				# if set, we jump to discrete char

offset_length:
	lbu	$v1,0($s1)	# load 16-bit length and match_position combo
	lbu	$a0,1($s1)	# can't use lhu because might be unaligned

	addiu	$s1,2		# increment source pointer

	sll	$a0,8
	or	$a0,$v1		# $a0 now has 16-bit value

	srl	$a1,$a0,P_BITS	# get the top bits, which is length

	addiu	$a1,$a1,THRESHOLD+1
	      			# add in the threshold

output_loop:
	li	$a3,(POSITION_MASK<<8+0xff)
	and	$a0,$a3
					# get the position bits

	lw	$a3,text_buf_addr
	addu	$a3,$a0
	lbu	$v1,0($a3)		# load byte from text_buf[]

	addiu	$a0,$a0,1	    	# advance pointer in text_buf

store_byte:
	sb	$v1,0($s0)		# store byte to output buffer
	addiu	$s0,1      		# increment pointer

	lw      $a3,text_buf_addr
	addu	$a3,$a2

	sb	$v1,0($a3)		# store also to text_buf[r]
	addiu 	$a2,$a2,1		# r++

	li	$a3,(N-1)
	and 	$a2,$a3		        # wrap r if we are too big

	addiu	$a1,$a1,-1		# decrement count

	bnez	$a1,output_loop		# repeat until k>j

					# OPTIMIZE: sltiu with > 8 bits
					#     takes 32bits?
	sltiu	$v1,$v0,0x100		# if 0 we shifted through 8 and must
	beqz	$v1,test_flags		# re-load flags

	b	decompression_loop


discrete_char:
	lbu	$v1,0($s1)		# load a byte
	addiu	$s1,1			# increment pointer
	li	$a1,1			# force a one-byte output
	b	store_byte		# and store it

# end of LZSS code

done_logo:
	lw	$a1,out_buffer_addr	# point $a1 to out_buffer
	jal	write_stdout		# print the logo

	la	$s1,strcat

#	j exit

first_line:
	#==========================
	# PRINT VERSION
	#==========================

	li	$v0, SYSCALL_UNAME		# uname syscall in $v0
	lw	$a0,uname_info_addr		# destination of uname in $a0
	syscall

	lw	$s0,out_buffer_addr		# point $16 to out_buffer

					# os-name from uname "Linux"
	lw	$a1,uname_info_addr
	#addiu	$a1,U_SYSNAME		U_SYSNAME is zero
	jalr	$s1			# strcat

					# source is " Version "
	lw	$a1,ver_string_addr
	jalr	$s1			# strcat

					# version from uname, ie "2.6.20"
	lw	$a1,uname_info_addr
	addiu	$a1,U_RELEASE
	jalr	$s1			# strcat

	lw	$a1,ver_string_addr
	addiu	$a1,(compiled_string-ver_string)
					# source is ", Compiled "
	jalr	$s1			# strcat

					# compiled date
	lw	$a1,uname_info_addr
	addiu	$a1,U_VERSION
	jalr	$s1			# strcat

	jal	center_and_print	# center and print

	#===============================
	# Middle-Line
	#===============================
middle_line:

	lw	$s0,out_buffer_addr	# point $16 to out_buffer

	#=========
	# Load /proc/cpuinfo into buffer
	#=========

	# syscalls are high enough to make loading the value take
	# extended instructions, which keeps them from going in
	# the branch delay slot.  So we use offsets instead.
	li	$v1,SYSCALL_LINUX
	addiu	$v0,$v1,(SYSCALL_OPEN-SYSCALL_LINUX)
					# open()

	lw	$a0,ver_string_addr
	addiu	$a0,(cpuinfo-ver_string)
					# '/proc/cpuinfo'
	li	$a1, 0			# 0 = O_RDONLY <bits/fcntl.h>

	syscall				# syscall.  fd in v0
					# we should check that
					# return v0>=0

	move	$a0,$v0			# copy $v0 (the result) to $a0

	addiu	$v0,$v1,(SYSCALL_READ-SYSCALL_LINUX)
					# read()

	lw	$a1,disk_buffer_addr	# point $a1 to the buffer
#	li	$a2, 4096		# 4096 should be more than enough
					# for this proc file

	li	$a2,128			# split it up so one can
	sll	$a2,5			# go in delay slot

	syscall

	addiu	$v0,$v1,(SYSCALL_CLOSE-SYSCALL_LINUX)
					# close (to be correct)
		    			# fd should still be in a0
	syscall

	# no reason not to do this here, while v1 still valid

	# didn't help this time, SYSCALL_SYSINFO too big to fit in 5 bits
	addiu	$v0,$v1,(SYSCALL_SYSINFO-SYSCALL_LINUX)
					# sysinfo() syscall
	lw	$a0, sysinfo_buff_addr
	syscall


	#=============
	# Number of CPUs
	#=============
number_of_cpus:

	# we cheat here and just assume 1.
	# besides, I don't have a SMP Mips machine to test on

	lw	$a1,ver_string_addr
	addiu	$a1,(one-ver_string)	# print "One MIPS "
	jalr	$s1			# strcat

	#=========
	# MHz
	#=========
print_mhz:

	# Mips /proc/cpuinfo does not indicate MHz


   	#=========
	# Chip Name
	#=========
chip_name:
   	lw	$a0,odel_string
					# find 'odel\t: ' and grab up to ' '
	li	$a3,' '
	jal	find_string

					# print "Processor, "
	lw	$a1,ver_string_addr
	addiu	$a1,(processor-ver_string)
	jalr	$s1			# strcat

	#========
	# RAM
	#========
ram:
	lw	$a0, sysinfo_buff_addr
	lw	$a0, S_TOTALRAM($a0)	# size in bytes of RAM

	srl	$a0,$a0,20		# divide by 1024*1024 to get M
					# note, splitting into two does
					# not help with delay slot
					# (still too big)
	li	$a3,1			# print to strcat, not stderr
	jal     num_to_ascii

					# print 'M RAM, '
	lw	$a1,ver_string_addr
	addiu	$a1,(ram_comma-ver_string)
	jalr	$s1			# strcat

	#========
	# Bogomips
	#========
bogomips:
   	lw	$a0,mips_string
					# find 'MIPS\t: ' and grab up to \n

	li	$a3, 0xa
	jal	find_string

					# bogo total follows RAM
	lw	$a1,ver_string_addr
	addiu	$a1,(bogo_total-ver_string)
	jalr	$s1			# strcat

	jal	center_and_print	# center and print


	#=================================
	# Print Host Name
	#=================================
hostname:
	lw	$s0,out_buffer_addr	# point $s0 to out_buffer

					# host name from uname()
	lw	$a1,uname_info_addr
	addiu	$a1,U_NODENAME
	jalr	$s1			# strcat

	jal	center_and_print	# center and print


					# (.txt) pointer to default_colors
	lw	$a1,ver_string_addr

	# Have to force the delay slot here, the assembler couldn't see it
.set noreorder
	jal	write_stdout
	addiu	$a1,(default_colors-ver_string)
.set reorder

	#================================
	# Exit
	#================================
exit:
	li	$v0,SYSCALL_EXIT	# put exit syscall in v0
	li	$a0,5			# put exit code in a0

	syscall

	#=================================
	# FIND_STRING
	#=================================
	#   $a3 is char to end at
	#   $a0 is 4-char ascii string to look for
	#   $s0 is the output buffer
	#
	#   $v0 is trashed

find_string:
	lw	$a2,disk_buffer_addr
					# look in cpuinfo buffer
find_loop:
	lw	$v0,1($a2)		# load un-aligned 32 bits
	addiu   $a2,$a2,1		# increment pointer
	beqz	$v0,done		# are we at EOF?
					# if so, done

	bne	$v0,$a0, find_loop	# do the strings match?
					# if not, loop

					# if we get this far, we matched

	li	$v1,':'
find_colon:
	lbu	$v0,1($a2)		# repeat till we find colon
	addiu	$a2,$a2,1

	beqz	$v0,done		# not found? then done

	bne	$v0,$v1,find_colon


	addiu   $a2,$a2,2		# skip a char [should be space]

store_loop:
	lbu	$v0,0($a2)		# load value
	addiu	$a2,$a2,1		# increment

	beqz	$v0,done		# off end, then stop

	beq	$v0,$a3,done		# is it end char?

	sb	$v0,0($s0)		# if not store and continue
	addiu	$s0,$s0,1		# increment output pointer
	b	store_loop		# loop

done:
	jr	$31			# return


nop	#needed for alignment issues?


	#================================
	# strcat
	#================================
	# string to cat a1
	# output_buffer s0
	# trashed v0


strcat:
	lbu	$v0,0($a1)		# load byte from string
	addiu	$a1,$a1,1		# increment string
	sb  	$v0,0($s0)		# store byte to output_buffer
	addiu	$s0,$s0,1		# increment output_buffer
	bnez	$v0,strcat		# if zero, we are done

done_strcat:
	addiu	$s0,$s0,-1		# correct pointer
	jr	$31			# return


nop	# needed for alignment?

	#==============================
	# center_and_print
	#==============================
	# string is in output_buffer
        #

center_and_print:

	move	$s2,$ra
	move	$s3,$s1			# save return address

	li	$v0,0xa00		# append linefeed
	sh	$v0,0($s0)

	lw	$a1,out_buffer_addr	# a1 is beginning of string
					# s0 is end of string

	subu	$s1,$s0,$a1		# subtract end pointer from start
       		    			# to get length

	slti	$v0,$s1,80

	beqz	$v0,done_center		# don't center if > 80

	neg	$s1  			# negate length



	lw	$a1,ver_string_addr

	# Have to force the delay slot here, the assembler couldn't see it
.set noreorder
	jal	write_stdout		# print ESCAPE char
	addiu	$a1,(escape-ver_string)
.set reorder

	addiu	$s1,80			# add to 80
	srl	$a0,$s1,1		# divide by 2


	li    	$a3,0 			# print to stdout
	jal	num_to_ascii		# print number of spaces



	lw	$a1,ver_string_addr

	# Have to force the delay slot here, the assembler couldn't see it
.set noreorder
	jal	write_stdout
	addiu	$a1,(c-ver_string)	# print "C"
.set reorder




done_center:
					# point to the string to print
	lw	$a1,out_buffer_addr

	move	$ra,$s2
	move	$s1,$s3
				# restore saved pointer
				# so we'll return to
				# where we were called from
				# at the end of the write_stdout


	#================================
	# WRITE_STDOUT
	#================================
	# a1 has the string


write_stdout:
	move	$s4,$ra
	move	$s5,$s1			# save return address

	move    $a0,$a1			# copy string pointer to $a0
	li      $a2,0			# 0 (count) in $a2

str_loop1:
	lbu	$v0,1($a0)		# load byte
	addiu	$a0,1
	addiu	$a2,1			# increment a2
	bnez	$v0,str_loop1		# if not nul, repeat

	li	$v0,SYSCALL_WRITE	# Write syscall in $v0
	li	$a0,STDOUT		# 1 in $a0 (stdout)

	syscall				# call syscall

	move	$ra,$s4
	move	$s1,$s5			# restore return address

	jr	$ra			# retrun


	##############################
	# num_to_ascii
	##############################
	# a0 = value to print
	# a1 = output buffer
	# a3 = stdout(0) or strcat(1)
	# destroys v1
num_to_ascii:

	lw	$a1,ascii_buff_addr	# point to end of ascii_buffer

div_by_10:
	addiu	$a1,$a1,-1	# point back one
	li	$v1,10		# divide by 10
	divu	$a0,$v1		# divide.  hi= remainder, lo=quotient
	mfhi	$v1		# remainder into v1
	addiu	$v1,0x30	# convert to ascii
	sb	$v1,0($a1)	# store to buffer
	mflo	$a0		# move old result into next divide
	bnez	$a0, div_by_10

write_out:

	beqz	$a3,write_stdout
				# if write stdout, go there
	b	strcat		# else, strcat will return for us



#===========================================================================
#	section .data
#===========================================================================
data_begin:
ver_string:		.ascii " Version \0"
compiled_string:	.ascii ", Compiled \0"
ram_comma:		.ascii "M RAM, \0"
bogo_total:		.ascii " Bogomips Total\0"
default_colors:		.ascii "\033[0m\n\0"
escape:			.ascii "\033[\0"
c:			.ascii "C\0"

cpuinfo:		.ascii "proc/cpu.mips\0"

one:			.ascii "One MIPS \0"
processor:		.ascii " Processor, \0"
odel_string:		.ascii "odel"
mips_string:		.ascii "MIPS"

.include	"logo.lzss_new"
			.byte 0,0	# note, without this
					# the assembler puts
					# logo_end in a weird
					# place which messes up
					# the end of the logo decode

out_buffer_addr:	.word out_buffer
text_buf_addr:		.word text_buf
uname_info_addr:	.word uname_info
ver_string_addr:	.word ver_string
disk_buffer_addr:	.word disk_buffer
sysinfo_buff_addr:	.word sysinfo_buff
ascii_buff_addr:	.word (ascii_buffer+10)

#============================================================================
#	section .bss
#============================================================================
.bss
.align 4
.lcomm	ascii_buffer,10		# 32 bit can't be > 9 chars
.lcomm	sysinfo_buff,128
.lcomm	uname_info,(65*6)
.lcomm	text_buf, (N+F-1)
.lcomm	disk_buffer,4096	# we cheat!!!!
.lcomm	out_buffer,16384

   # see /usr/src/linux/include/linux/kernel.h

