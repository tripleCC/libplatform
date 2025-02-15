/*
 * Copyright (c) 2011-2017 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

#include <mach/arm/syscall_sw.h>
#include <mach/arm64/asm.h>
#include <machine/cpu_capabilities.h>

#define MMU_I_CLINE	6		// cache line size as 1<<MMU_I_CLINE (64)

/* void sys_icache_invalidate(void *start, size_t length) */
.globl	_sys_icache_invalidate
.p2align	2
_sys_icache_invalidate:
	// see InvalidatePoU_IcacheRegion() in xnu/osfmk/arm64/caches_asm.s
	cbz		x1, 2f							// length > 0 ?

	and		x9, x0, #~((1<<MMU_I_CLINE)-1)	// cacheline align address
	and		x10, x0, #((1<<MMU_I_CLINE)-1)	// extend length by alignment
	add		x10, x1, x10
	sub		x10, x10, #1
	mov		x11, #-1
	eor		x10, x11, x10, lsr #MMU_I_CLINE	// compute cacheline counter
	dsb		ish
	mov		x2, #20
	mov		x3, #0							//0 = do not know, nonzero = we know
1:
	ic		ivau, x9						// invalidate icache line
	add		x9, x9, #1<<MMU_I_CLINE			// next cacheline address
	subs	x2, x2, #1
	b.ne	3f

	//we did some invalidates, time to maybe DSB?
	cbz		x3, 8f
4:											//we need it
	dsb		ish
	mov		x2, #20

3:
	adds	x10, x10, #1					// decrement cacheline counter
	b.ne	1b
	dsb		ish
	isb
2:
	ret

8:
	MOV64	x8, _COMM_PAGE_CPUFAMILY
	ldr		w8, [x8]
	adrp	x2, EXT(cpus_that_need_dsb_for_ic_ivau)@page
	add		x2, x2, EXT(cpus_that_need_dsb_for_ic_ivau)@pageoff
1:
	ldr		w3, [x2], #4
	cbz		w3, 2f
	cmp		w3, w8
	b.eq	4b								//match
	b		1b

2:											//no match
	mov		x2, #0
	mov		x3, #1
	b		3b


_cpus_that_need_dsb_for_ic_ivau:
		.word 0x1b588bb3
		.word 0xda33d83d
		.word 0x8765edea
		.word 0xfa33415e
		.word 0x2876f5b5
		.word 0x72015832
		.word 0x5f4dea93
		.word 0

/* void sys_dcache_flush(void *start, size_t length) */
.globl	_sys_dcache_flush
.p2align	2
_sys_dcache_flush:
	// see FlushPoC_DcacheRegion() in xnu/osfmk/arm64/caches_asm.s
	dsb		ish								// noop, we are fully coherent
	ret

#if 0
// Above based on output generated by clang from:
static void __attribute((used))
sys_icache_invalidate(uintptr_t start, size_t length)
{
	if (!length) return;
	boolean_t hasICDSB = (*(uint32_t*)(uintptr_t)_COMM_PAGE_CPU_CAPABILITIES) & kHasICDSB;
	uintptr_t addr = start & ~((1 << MMU_I_CLINE) - 1);
	length += start & ((1 << MMU_I_CLINE) - 1);
	size_t count = ((length - 1) >> MMU_I_CLINE) + 1;
	asm volatile("dsb ish" ::: "memory");
	while (count--) {
		asm("ic ivau, %[addr]" :: [addr] "r" (addr) : "memory");
		addr += (1 << MMU_I_CLINE);
	}
	if (hasICDSB) {
		asm volatile("dsb ish" ::: "memory");
	} else {
		asm volatile("dsb ish" ::: "memory");
		asm volatile("isb" ::: "memory");
	}
}

cbz    x1, 0x44
mov    x8, #0xfffff0000
movk   x8, #0xc020
ldr    w8, [x8]
and    x9, x0, #0xffffffffffffffc0
and    x10, x0, #0x3f
add    x10, x1, x10
sub    x10, x10, #0x1
mov    x11, #-0x1
eor    x10, x11, x10, lsr #6
ic     ivau, x9
add    x9, x9, #0x40
adds   x10, x10, #0x1
b.ne   0x28
dsb    ish
tbnz   w8, #0x2, 0x44
isb
ret

#endif

