!
! SYS_SIZE is the number of clicks (16 bytes) to be loaded.
! 0x3000 is 0x30000 bytes = 196kB, more than enough for current
! versions of linux
!这里'!'或';' 表示程序注释语句的开始
SYSSIZE = 0x3000
!
!	bootsect.s		(C) 1991 Linus Torvalds									bootsect.s的框架程序，
!
! bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
! iself out of the way to address 0x90000, and jumps there.
!bootsect.s被bios-启动子程序加载到0x7c00(31KB)处，并将自己移到了地址0x90000(576KB)处，并跳转至那里
!
! It then loads 'setup' directly after itself (0x90200), and the system
! at 0x10000, using BIOS interrupts. 
!它然后使用BIOS中断将'setup'直接加载到自己的后面(0x90200)(576.5KB),并将system加载到地址0x10000处
!
! NOTE! currently system is at most 8*65536 bytes long. This should be no
! problem, even in the future. I want to keep it simple. This 512 kB
! kernel size should be enough, especially as this doesn't contain the
! buffer cache as in minix
!注意!目前的内核系统最大长度限制为(8*65536)(512KB)字节,即使是在将来这也应该没有问题的,我想让它保持简单明了.这样512KB的最大内核长度应该足够了,尤其是这里没有象minix中一样包含高速缓冲区
!
! The loader has been made as simple as possible, and continuos
! read errors will result in a unbreakable loop. Reboot by hand. It
! loads pretty fast by getting whole sectors at a time whenever possible.
!加载程序已经做得够简单了,所以持续的读出错将导致死循环.只能手动重启.只要可能,通过一次读取所有的扇区,加载过程可以做得很快

.globl begtext, begdata, begbss, endtext, enddata, endbss					!全局标识符，供ld86链接使用
.text																		!正文段
begtext:
.data																		!数据段
begdata:
.bss																		!未初始化数据段
begbss:
.text																		!正文段

SETUPLEN = 4				! nr of setup-sectors							setup程序的扇区数(setup-sectors)值
BOOTSEG  = 0x07c0			! original address of boot-sector				BIOS 加载bootsect 代码的原始段地址
INITSEG  = 0x9000			! we move boot here - out of the way			将bootsect移到这里 -- 避开
SETUPSEG = 0x9020			! setup starts here								setup程序从这里开始
SYSSEG   = 0x1000			! system loaded at 0x10000 (65536).				system模块加载到0x10000(64KB)处
ENDSEG   = SYSSEG + SYSSIZE		! where to stop loading						停止加载的段地址

! ROOT_DEV:	0x000 - same type of floppy as boot.							根文件系统设备使用与引导时同样的软驱设备
!		0x301 - first partition on first drive etc							根文件系统设备在第一个硬盘的第一个分区上
ROOT_DEV = 0x306

entry start																	!告知链接程序，程序从start标号处开始执行
start:
	mov	ax,#BOOTSEG															!传送#BOOTSEG 到 ax
	mov	ds,ax	
	mov	ax,#INITSEG
	mov	es,ax
	mov	cx,#256
	sub	si,si
	sub	di,di
	rep
	movw
	jmpi	go,INITSEG														!段间跳转。INITSEG指出跳转地址，标号go是偏移地址
go:	mov	ax,cs																!段寄存器cs值-->ax,用与初始化段寄存器ds和es
	mov	ds,ax
	mov	es,ax
! put stack at 0x9ff00.														将堆栈指针sp指向0x9ff00(即0x9000:0xff00)处
	mov	ss,ax
	mov	sp,#0xFF00		! arbitrary value >>512

! load the setup-sectors directly after the bootblock.						在bootsect 程序块后紧跟着加载setup模块的代码数据
! Note that 'es' is already set up.											注意es已经设置好了

load_setup:
	mov	dx,#0x0000		! drive 0, head 0									
	mov	cx,#0x0002		! sector 2, track 0
	mov	bx,#0x0200		! address = 512, in INITSEG
	mov	ax,#0x0200+SETUPLEN	! service 2, nr of sectors
	int	0x13			! read it
	jnc	ok_load_setup		! ok - continue
	mov	dx,#0x0000
	mov	ax,#0x0000		! reset the diskette
	int	0x13
	j	load_setup

ok_load_setup:	

! Get disk drive parameters, specifically nr of sectors/track				取磁盘驱动器的参数,特别是每道的扇区数量

	mov	dl,#0x00
	mov	ax,#0x0800		! AH=8 is get drive parameters						获取驱动器参数
	int	0x13
	mov	ch,#0x00
	seg cs
	mov	sectors,cx
	mov	ax,#INITSEG
	mov	es,ax

! Print some inane message

	mov	ah,#0x03		! read cursor pos
	xor	bh,bh
	int	0x10
	
	mov	cx,#24
	mov	bx,#0x0007		! page 0, attribute 7 (normal)
	mov	bp,#msg1
	mov	ax,#0x1301		! write string, move cursor
	int	0x10

! ok, we've written the message, now
! we want to load the system (at 0x10000)

	mov	ax,#SYSSEG
	mov	es,ax		! segment of 0x010000
	call	read_it
	call	kill_motor

! After that we check which root-device to use. If the device is
! defined (!= 0), nothing is done and the given device is used.
! Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
! on the number of sectors that the BIOS reports currently.

	seg cs
	mov	ax,root_dev
	cmp	ax,#0
	jne	root_defined
	seg cs
	mov	bx,sectors
	mov	ax,#0x0208		! /dev/ps0 - 1.2Mb
	cmp	bx,#15
	je	root_defined
	mov	ax,#0x021c		! /dev/PS0 - 1.44Mb
	cmp	bx,#18
	je	root_defined
undef_root:
	jmp undef_root
root_defined:
	seg cs
	mov	root_dev,ax

! after that (everyting loaded), we jump to
! the setup-routine loaded directly after
! the bootblock:

	jmpi	0,SETUPSEG

! This routine loads the system at address 0x10000, making sure
! no 64kB boundaries are crossed. We try to load it as fast as
! possible, loading whole tracks whenever we can.
!
! in:	es - starting address segment (normally 0x1000)
!
sread:	.word 1+SETUPLEN	! sectors read of current track
head:	.word 0			! current head
track:	.word 0			! current track

read_it:
	mov ax,es
	test ax,#0x0fff
die:	jne die			! es must be at 64kB boundary
	xor bx,bx		! bx is starting address within segment
rp_read:
	mov ax,es
	cmp ax,#ENDSEG		! have we loaded all yet?
	jb ok1_read
	ret
ok1_read:
	seg cs
	mov ax,sectors
	sub ax,sread
	mov cx,ax
	shl cx,#9
	add cx,bx
	jnc ok2_read
	je ok2_read
	xor ax,ax
	sub ax,bx
	shr ax,#9
ok2_read:
	call read_track
	mov cx,ax
	add ax,sread
	seg cs
	cmp ax,sectors
	jne ok3_read
	mov ax,#1
	sub ax,head
	jne ok4_read
	inc track
ok4_read:
	mov head,ax
	xor ax,ax
ok3_read:
	mov sread,ax
	shl cx,#9
	add bx,cx
	jnc rp_read
	mov ax,es
	add ax,#0x1000
	mov es,ax
	xor bx,bx
	jmp rp_read

read_track:
	push ax
	push bx
	push cx
	push dx
	mov dx,track
	mov cx,sread
	inc cx
	mov ch,dl
	mov dx,head
	mov dh,dl
	mov dl,#0
	and dx,#0x0100
	mov ah,#2
	int 0x13
	jc bad_rt
	pop dx
	pop cx
	pop bx
	pop ax
	ret
bad_rt:	mov ax,#0
	mov dx,#0
	int 0x13
	pop dx
	pop cx
	pop bx
	pop ax
	jmp read_track

/*
 * This procedure turns off the floppy drive motor, so
 * that we enter the kernel in a known state, and
 * don't have to worry about it later.
 */
kill_motor:
	push dx
	mov dx,#0x3f2
	mov al,#0
	outb
	pop dx
	ret

sectors:
	.word 0

msg1:
	.byte 13,10
	.ascii "Loading system ..."
	.byte 13,10,13,10

.org 508
root_dev:
	.word ROOT_DEV
boot_flag:
	.word 0xAA55

.text
endtext:
.data
enddata:
.bss
endbss:
