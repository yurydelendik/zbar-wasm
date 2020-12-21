/*
 * Wasm SIMD optimizations for libjpeg-turbo
 *
 * Copyright (C) 2020, Mozilla Foundation.  All Rights Reserved.
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 */

#define FAKE_32DOT

/* Supplementary macro for setting function attributes */
.macro asm_function fname, params, returns
    .global \fname
    .hidden \fname
    .type \fname, @function
\fname:
    .functype   \fname \params -> \returns
.endm

#define F_0_298   2446  /* FIX(0.298631336) */
#define F_0_390   3196  /* FIX(0.390180644) */
#define F_0_541   4433  /* FIX(0.541196100) */
#define F_0_765   6270  /* FIX(0.765366865) */
#define F_0_899   7373  /* FIX(0.899976223) */
#define F_1_175   9633  /* FIX(1.175875602) */
#define F_1_501  12299  /* FIX(1.501321110) */
#define F_1_847  15137  /* FIX(1.847759065) */
#define F_1_961  16069  /* FIX(1.961570560) */
#define F_2_053  16819  /* FIX(2.053119869) */
#define F_2_562  20995  /* FIX(2.562915447) */
#define F_3_072  25172  /* FIX(3.072711026) */

#define F130_F054 10703   /* (F_0_541 + F_0_765) */
#define F054_MF130 -10704 /* (F_0_541 - F_1_847) */
#define F117_M196 -6436 /* (F_1_175 - F_1_961) */
#define F117_MF039 6437 /* (F_1_175 - F_0_390) */
#define F029_MF089 -4927 /* (F_0_298 - F_0_899) */
#define F150_MF089 4926 /* (F_1_501 - F_0_899) */
#define F205_MF256 -4176 /* (F_2_053 - F_2_562) */
#define F307_MF256 4177 /* (F_3_072 - F_2_562) */

#define V128_PW_F130_F054   F130_F054, F_0_541, F130_F054, F_0_541, F130_F054, F_0_541, F130_F054, F_0_541
#define V128_PW_F054_MF130  F_0_541, F054_MF130, F_0_541, F054_MF130, F_0_541, F054_MF130, F_0_541, F054_MF130
#define V128_PW_MF078_F117  F117_M196, F_1_175, F117_M196, F_1_175, F117_M196, F_1_175, F117_M196, F_1_175
#define V128_PW_F117_F078   F_1_175, F117_MF039, F_1_175, F117_MF039,  F_1_175, F117_MF039,  F_1_175, F117_MF039
#define V128_PW_MF060_MF089 F029_MF089, -F_0_899, F029_MF089, -F_0_899, F029_MF089, -F_0_899, F029_MF089, -F_0_899
#define V128_PW_MF089_F060  -F_0_899, F150_MF089, -F_0_899, F150_MF089, -F_0_899, F150_MF089, -F_0_899, F150_MF089
#define V128_PW_MF050_MF256 F205_MF256, -F_2_562, F205_MF256, -F_2_562, F205_MF256, -F_2_562, F205_MF256, -F_2_562
#define V128_PW_MF256_F050  -F_2_562, F307_MF256, -F_2_562, F307_MF256, -F_2_562, F307_MF256, -F_2_562, F307_MF256

#define CONST_BITS 13
#define C16_MCONST_BITS 3

#define PASS1_BITS  2
#define DESCALE_P1  11 /* (CONST_BITS - PASS1_BITS) */
#define DESCALE_P2  18 /* (CONST_BITS + PASS1_BITS + 3) */

#define PD_DESCALE_P1  1024 /* 1 << (DESCALE_P1 - 1) */
#define PD_DESCALE_P2  131072 /* 1 << (DESCALE_P2 - 1) */

#define CENTERJSAMPLE   128


    .text
#define xmm0 4
#define xmm1 5
#define xmm2 6
#define xmm3 7
#define xmm4 8
#define xmm5 9
#define xmm6 10
#define xmm7 11
#define wk0 12
#define wk1 13
#define wk2 14
#define wk3 15
#define wk4 16
#define wk5 17
#define wk6 18
#define wk7 19
#define wk8 20
#define wk9 21
#define wk10 22
#define wk11 23

#define quantptr 0 
#define inptr 1
#define output_buf 2
// quantptr rdx, inptr rsi

.macro movdqa dest, src
    local.get \src
    local.set \dest
.endm

.macro movdqa_l dest, src, ofs
    local.get \src
    v128.load \ofs
    local.set \dest
.endm

.macro movdqa_s dest, ofs, src
    local.get \src
    local.get \dest
    v128.store \ofs
.endm

.macro movdqa_c dest, imm
    i32.const   \imm
    i32x4.splat
    local.set \dest
.endm

.macro pmullw dest, src, ofs
    local.get \dest
    local.get \src
    v128.load \ofs
    i16x8.mul
    local.set \dest
.endm

.macro punpcklwd dest, src
    local.get \dest
    local.get \src
    v8x16.shuffle 0,1,16,17,2,3,18,19,4,5,20,21,6,7,22,23
    local.set \dest
.endm

.macro punpckhwd dest, src
    local.get \dest
    local.get \src
    v8x16.shuffle 8,9,24,25,10,11,26,27,12,13,28,29,14,15,30,31
    local.set \dest
.endm

.macro punpckldq dest, src
    local.get \dest
    local.get \src
    v8x16.shuffle 0,1,2,3,16,17,18,19,4,5,6,7,20,21,22,23
    local.set \dest
.endm

.macro punpckhdq dest, src
    local.get \dest
    local.get \src
    v8x16.shuffle 8,9,10,11,24,25,26,27,12,13,14,15,28,29,30,31
    local.set \dest
.endm

.macro punpcklqdq dest, src
    local.get \dest
    local.get \src
    v8x16.shuffle 0,1,2,3,4,5,6,7,16,17,18,19,20,21,22,23
    local.set \dest
.endm

.macro punpckhqdq dest, src
    local.get \dest
    local.get \src
    v8x16.shuffle 8,9,10,11,12,13,14,15,24,25,26,27,28,29,30,31
    local.set \dest
.endm

.macro punpcklbw dest, src
    local.get \dest
    local.get \src
    v8x16.shuffle 0,16,1,17,2,18,3,19,4,20,5,21,6,22,7,23
    local.set \dest
.endm

.macro punpckhbw dest, src
    local.get \dest
    local.get \src
    v8x16.shuffle 8,24,9,25,10,26,11,27,12,28,13,29,14,30,15,31
    local.set \dest
.endm


.macro pshufd_4e dest, src
    local.get \src
    v128.const 0x1234567, 0x1234567, 0x1234567, 0x1234567
    v8x16.shuffle 8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7
    local.set \dest
.endm

.macro pmaddwd dest, c:vararg
#ifdef FAKE_32DOT
    local.get \dest
    i16x8.extract_lane_s 0
    v128.const \c
    i16x8.extract_lane_s 0
    i32.mul
    local.get \dest
    i16x8.extract_lane_s 1
    v128.const \c
    i16x8.extract_lane_s 1
    i32.mul
    i32.add
    i32x4.splat

    local.get \dest
    i16x8.extract_lane_s 2
    v128.const \c
    i16x8.extract_lane_s 2
    i32.mul
    local.get \dest
    i16x8.extract_lane_s 3
    v128.const \c
    i16x8.extract_lane_s 3
    i32.mul
    i32.add
    i32x4.replace_lane 1

    local.get \dest
    i16x8.extract_lane_s 4
    v128.const \c
    i16x8.extract_lane_s 4
    i32.mul
    local.get \dest
    i16x8.extract_lane_s 5
    v128.const \c
    i16x8.extract_lane_s 5
    i32.mul
    i32.add
    i32x4.replace_lane 2

    local.get \dest
    i16x8.extract_lane_s 6
    v128.const \c
    i16x8.extract_lane_s 6
    i32.mul
    local.get \dest
    i16x8.extract_lane_s 7
    v128.const \c
    i16x8.extract_lane_s 7
    i32.mul
    i32.add
    i32x4.replace_lane 3

#else
    local.get \dest
    v128.const \c
    i32x4.dot_i16x8_s
#endif
    local.set \dest
.endm

.macro paddw dest, src
    local.get \dest
    local.get \src
    i16x8.add
    local.set \dest
.endm

.macro psubw dest, src
    local.get \dest
    local.get \src
    i16x8.sub
    local.set \dest
.endm

.macro paddd dest, src
    local.get \dest
    local.get \src
    i32x4.add
    local.set \dest
.endm

.macro psubd dest, src
    local.get \dest
    local.get \src
    i32x4.sub
    local.set \dest
.endm

.macro paddb dest, src
    local.get \dest
    local.get \src
    i8x16.add
    local.set \dest
.endm

.macro psubb dest, src
    local.get \dest
    local.get \src
    i8x18.sub
    local.set \dest
.endm

.macro pxor dest, src
    local.get \dest
    local.get \src
    v128.xor
    local.set \dest
.endm

.macro psrad dest, imm
    local.get \dest
    i32.const \imm
    i32x4.shr_s
    local.set \dest
.endm

.macro packssdw dest, src
    local.get \dest
    local.get \src
    i16x8.narrow_i32x4_s
    local.set \dest
.endm

.macro packsswb dest, src
    local.get \dest
    local.get \src
    i8x16.narrow_i16x8_s
    local.set \dest
.endm

.macro store_row ofs, src
    local.get 2
    i32.load \ofs
    local.get 3
    i32.add
    local.get \src
    v128.store 0
.endm

.macro store_row_mm ofs, src
    local.get 2
    i32.load \ofs
    local.get 3
    i32.add
    local.get \src
    i64x2.extract_lane 0
    i64.store 0
.endm

asm_function jsimd_idct_islow_wasm (i32,i32,i32,i32) (i32)
    .local     v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128, v128

    block

    // -- Even part

    movdqa_l    xmm0, inptr, 0 // XMMWORD [XMMBLOCK(0,0,rsi,SIZEOF_JCOEF)]
    movdqa_l    xmm1, inptr, 32 // XMMWORD [XMMBLOCK(2,0,rsi,SIZEOF_JCOEF)]
    pmullw      xmm0, quantptr, 0 // XMMWORD [XMMBLOCK(0,0,rdx,SIZEOF_ISLOW_MULT_TYPE)]
    pmullw      xmm1, quantptr, 32 // XMMWORD [XMMBLOCK(2,0,rdx,SIZEOF_ISLOW_MULT_TYPE)]
    movdqa_l    xmm2, inptr, 64 // XMMWORD [XMMBLOCK(4,0,rsi,SIZEOF_JCOEF)]
    movdqa_l    xmm3, inptr, 96 // XMMWORD [XMMBLOCK(6,0,rsi,SIZEOF_JCOEF)]
    pmullw      xmm2, quantptr, 64 //XMMWORD [XMMBLOCK(4,0,rdx,SIZEOF_ISLOW_MULT_TYPE)]
    pmullw      xmm3, quantptr, 96 //XMMWORD [XMMBLOCK(6,0,rdx,SIZEOF_ISLOW_MULT_TYPE)]

    // (Original)
    // z1 = (z2 + z3) * 0.541196100;
    // tmp2 = z1 + z3 * -1.847759065;
    // tmp3 = z1 + z2 * 0.765366865;
    //
    // (This implementation)
    // tmp2 = z2 * 0.541196100 + z3 * (0.541196100 - 1.847759065);
    // tmp3 = z2 * (0.541196100 + 0.765366865) + z3 * 0.541196100;

    movdqa      xmm4, xmm1              // xmm1=in2=z2
    movdqa      xmm5, xmm1
    punpcklwd   xmm4, xmm3              // xmm3=in6=z3
    punpckhwd   xmm5, xmm3
    movdqa      xmm1, xmm4
    movdqa      xmm3, xmm5
    pmaddwd     xmm4, V128_PW_F130_F054 // xmm4=tmp3L
    pmaddwd     xmm5, V128_PW_F130_F054 // xmm5=tmp3H
    pmaddwd     xmm1, V128_PW_F054_MF130  // xmm1=tmp2L
    pmaddwd     xmm3, V128_PW_F054_MF130  // xmm3=tmp2H

    movdqa      xmm6, xmm0
    paddw       xmm0, xmm2              // xmm0=in0+in4
    psubw       xmm6, xmm2              // xmm6=in0-in4

    pxor        xmm7, xmm7
    pxor        xmm2, xmm2
    punpcklwd   xmm7, xmm0              // xmm7=tmp0L
    punpckhwd   xmm2, xmm0              // xmm2=tmp0H

    psrad       xmm7, C16_MCONST_BITS   // psrad xmm7,16 & pslld xmm7,CONST_BITS
    psrad       xmm2, C16_MCONST_BITS   // psrad xmm2,16 & pslld xmm2,CONST_BITS

    movdqa      xmm0, xmm7
    paddd       xmm7, xmm4              // xmm7=tmp10L
    psubd       xmm0, xmm4              // xmm0=tmp13L
    movdqa      xmm4, xmm2
    paddd       xmm2, xmm5              // xmm2=tmp10H
    psubd       xmm4, xmm5              // xmm4=tmp13H

    movdqa      wk0, xmm7   // wk(0)=tmp10L
    movdqa      wk1, xmm2   // wk(1)=tmp10H
    movdqa      wk2, xmm0   // wk(2)=tmp13L
    movdqa      wk3, xmm4   // wk(3)=tmp13H

    pxor        xmm5, xmm5
    pxor        xmm7, xmm7
    punpcklwd   xmm5, xmm6              // xmm5=tmp1L
    punpckhwd   xmm7, xmm6              // xmm7=tmp1H
    psrad       xmm5, C16_MCONST_BITS   // psrad xmm5,16 & pslld xmm5,CONST_BITS
    psrad       xmm7, C16_MCONST_BITS   // psrad xmm7,16 & pslld xmm7,CONST_BITS

    movdqa      xmm2, xmm5
    paddd       xmm5, xmm1              // xmm5=tmp11L
    psubd       xmm2, xmm1              // xmm2=tmp12L
    movdqa      xmm0, xmm7
    paddd       xmm7, xmm3              // xmm7=tmp11H
    psubd       xmm0, xmm3              // xmm0=tmp12H

    movdqa      wk4, xmm5   // wk(4)=tmp11L
    movdqa      wk5, xmm7   // wk(5)=tmp11H
    movdqa      wk6, xmm2   // wk(6)=tmp12L
    movdqa      wk7, xmm0   // wk(7)=tmp12H

    // -- Odd part

    movdqa_l    xmm4, inptr, 16 // XMMWORD [XMMBLOCK(1,0,rsi,SIZEOF_JCOEF)]
    movdqa_l    xmm6, inptr, 48 // XMMWORD [XMMBLOCK(3,0,rsi,SIZEOF_JCOEF)]
    pmullw      xmm4, quantptr, 16 // XMMWORD [XMMBLOCK(1,0,rdx,SIZEOF_ISLOW_MULT_TYPE)]
    pmullw      xmm6, quantptr, 48 // XMMWORD [XMMBLOCK(3,0,rdx,SIZEOF_ISLOW_MULT_TYPE)]
    movdqa_l    xmm1, inptr, 80 // XMMWORD [XMMBLOCK(5,0,rsi,SIZEOF_JCOEF)]
    movdqa_l    xmm3, inptr, 112 // XMMWORD [XMMBLOCK(7,0,rsi,SIZEOF_JCOEF)]
    pmullw      xmm1, quantptr, 80 // XMMWORD [XMMBLOCK(5,0,rdx,SIZEOF_ISLOW_MULT_TYPE)]
    pmullw      xmm3, quantptr, 112 // XMMWORD [XMMBLOCK(7,0,rdx,SIZEOF_ISLOW_MULT_TYPE)]

    movdqa      xmm5, xmm6
    movdqa      xmm7, xmm4
    paddw       xmm5, xmm3              // xmm5=z3
    paddw       xmm7, xmm1              // xmm7=z4

    // (Original)
    // z5 = (z3 + z4) * 1.175875602;
    // z3 = z3 * -1.961570560;  z4 = z4 * -0.390180644;
    // z3 += z5;  z4 += z5;
    //
    // (This implementation)
    // z3 = z3 * (1.175875602 - 1.961570560) + z4 * 1.175875602;
    // z4 = z3 * 1.175875602 + z4 * (1.175875602 - 0.390180644);

    movdqa      xmm2, xmm5
    movdqa      xmm0, xmm5
    punpcklwd   xmm2, xmm7
    punpckhwd   xmm0, xmm7
    movdqa      xmm5, xmm2
    movdqa      xmm7, xmm0
    pmaddwd     xmm2, V128_PW_MF078_F117  // xmm2=z3L
    pmaddwd     xmm0, V128_PW_MF078_F117  // xmm0=z3H
    pmaddwd     xmm5, V128_PW_F117_F078   // xmm5=z4L
    pmaddwd     xmm7, V128_PW_F117_F078   // xmm7=z4H

    movdqa      wk10, xmm2  // wk(10)=z3L
    movdqa      wk11, xmm0  // wk(11)=z3H

    // (Original)
    // z1 = tmp0 + tmp3;  z2 = tmp1 + tmp2;
    // tmp0 = tmp0 * 0.298631336;  tmp1 = tmp1 * 2.053119869;
    // tmp2 = tmp2 * 3.072711026;  tmp3 = tmp3 * 1.501321110;
    // z1 = z1 * -0.899976223;  z2 = z2 * -2.562915447;
    // tmp0 += z1 + z3;  tmp1 += z2 + z4;
    // tmp2 += z2 + z3;  tmp3 += z1 + z4;
    //
    // (This implementation)
    // tmp0 = tmp0 * (0.298631336 - 0.899976223) + tmp3 * -0.899976223;
    // tmp1 = tmp1 * (2.053119869 - 2.562915447) + tmp2 * -2.562915447;
    // tmp2 = tmp1 * -2.562915447 + tmp2 * (3.072711026 - 2.562915447);
    // tmp3 = tmp0 * -0.899976223 + tmp3 * (1.501321110 - 0.899976223);
    // tmp0 += z3;  tmp1 += z4;
    // tmp2 += z3;  tmp3 += z4;

    movdqa      xmm2, xmm3
    movdqa      xmm0, xmm3
    punpcklwd   xmm2, xmm4
    punpckhwd   xmm0, xmm4
    movdqa      xmm3, xmm2
    movdqa      xmm4, xmm0

    pmaddwd     xmm2, V128_PW_MF060_MF089  // xmm2=tmp0L
    pmaddwd     xmm0, V128_PW_MF060_MF089  // xmm0=tmp0H
    pmaddwd     xmm3, V128_PW_MF089_F060   // xmm3=tmp3L
    pmaddwd     xmm4, V128_PW_MF089_F060   // xmm4=tmp3H

    paddd       xmm2, wk10  // xmm2=tmp0L
    paddd       xmm0, wk11  // xmm0=tmp0H
    paddd       xmm3, xmm5              // xmm3=tmp3L
    paddd       xmm4, xmm7              // xmm4=tmp3H

    movdqa      wk8, xmm2   // wk(8)=tmp0L
    movdqa      wk9, xmm0   // wk(9)=tmp0H

    movdqa      xmm2, xmm1
    movdqa      xmm0, xmm1
    punpcklwd   xmm2, xmm6
    punpckhwd   xmm0, xmm6
    movdqa      xmm1, xmm2
    movdqa      xmm6, xmm0
    pmaddwd     xmm2, V128_PW_MF050_MF256  // xmm2=tmp1L
    pmaddwd     xmm0, V128_PW_MF050_MF256  // xmm0=tmp1H
    pmaddwd     xmm1, V128_PW_MF256_F050   // xmm1=tmp2L
    pmaddwd     xmm6, V128_PW_MF256_F050   // xmm6=tmp2H

    paddd       xmm2, xmm5              // xmm2=tmp1L
    paddd       xmm0, xmm7              // xmm0=tmp1H
    paddd       xmm1, wk10  // xmm1=tmp2L
    paddd       xmm6, wk11  // xmm6=tmp2H

    movdqa      wk10, xmm2  // wk(10)=tmp1L
    movdqa      wk11, xmm0  // wk(11)=tmp1H

    // -- Final output stage

    movdqa      xmm5, wk0   // xmm5=tmp10L
    movdqa      xmm7, wk1   // xmm7=tmp10H

    movdqa      xmm2, xmm5
    movdqa      xmm0, xmm7
    paddd       xmm5, xmm3              // xmm5=data0L
    paddd       xmm7, xmm4              // xmm7=data0H
    psubd       xmm2, xmm3              // xmm2=data7L
    psubd       xmm0, xmm4              // xmm0=data7H

    movdqa_c      xmm3, PD_DESCALE_P1

    paddd       xmm5, xmm3
    paddd       xmm7, xmm3
    psrad       xmm5, DESCALE_P1
    psrad       xmm7, DESCALE_P1
    paddd       xmm2, xmm3
    paddd       xmm0, xmm3
    psrad       xmm2, DESCALE_P1
    psrad       xmm0, DESCALE_P1

    packssdw    xmm5, xmm7              // xmm5=data0=(00 01 02 03 04 05 06 07)
    packssdw    xmm2, xmm0              // xmm2=data7=(70 71 72 73 74 75 76 77)

    movdqa      xmm4, wk4   // xmm4=tmp11L
    movdqa      xmm3, wk5   // xmm3=tmp11H

    movdqa      xmm7, xmm4
    movdqa      xmm0, xmm3
    paddd       xmm4, xmm1              // xmm4=data1L
    paddd       xmm3, xmm6              // xmm3=data1H
    psubd       xmm7, xmm1              // xmm7=data6L
    psubd       xmm0, xmm6              // xmm0=data6H

    movdqa_c      xmm1, PD_DESCALE_P1  // xmm1=[rel PD_DESCALE_P1]

    paddd       xmm4, xmm1
    paddd       xmm3, xmm1
    psrad       xmm4, DESCALE_P1
    psrad       xmm3, DESCALE_P1
    paddd       xmm7, xmm1
    paddd       xmm0, xmm1
    psrad       xmm7, DESCALE_P1
    psrad       xmm0, DESCALE_P1

    packssdw    xmm4, xmm3              // xmm4=data1=(10 11 12 13 14 15 16 17)
    packssdw    xmm7, xmm0              // xmm7=data6=(60 61 62 63 64 65 66 67)

    movdqa      xmm6, xmm5              // transpose coefficients(phase 1)
    punpcklwd   xmm5, xmm4              // xmm5=(00 10 01 11 02 12 03 13)
    punpckhwd   xmm6, xmm4              // xmm6=(04 14 05 15 06 16 07 17)
    movdqa      xmm1, xmm7              // transpose coefficients(phase 1)
    punpcklwd   xmm7, xmm2              // xmm7=(60 70 61 71 62 72 63 73)
    punpckhwd   xmm1, xmm2              // xmm1=(64 74 65 75 66 76 67 77)

    movdqa      xmm3, wk6   // xmm3=tmp12L
    movdqa      xmm0, wk7   // xmm0=tmp12H
    movdqa      xmm4, wk10  // xmm4=tmp1L
    movdqa      xmm2, wk11  // xmm2=tmp1H

    movdqa      wk0, xmm5   // wk(0)=(00 10 01 11 02 12 03 13)
    movdqa      wk1, xmm6   // wk(1)=(04 14 05 15 06 16 07 17)
    movdqa      wk4, xmm7   // wk(4)=(60 70 61 71 62 72 63 73)
    movdqa      wk5, xmm1   // wk(5)=(64 74 65 75 66 76 67 77)

    movdqa      xmm5, xmm3
    movdqa      xmm6, xmm0
    paddd       xmm3, xmm4              // xmm3=data2L
    paddd       xmm0, xmm2              // xmm0=data2H
    psubd       xmm5, xmm4              // xmm5=data5L
    psubd       xmm6, xmm2              // xmm6=data5H

    movdqa_c      xmm7, PD_DESCALE_P1 // xmm7=[rel PD_DESCALE_P1]

    paddd       xmm3, xmm7
    paddd       xmm0, xmm7
    psrad       xmm3, DESCALE_P1
    psrad       xmm0, DESCALE_P1
    paddd       xmm5, xmm7
    paddd       xmm6, xmm7
    psrad       xmm5, DESCALE_P1
    psrad       xmm6, DESCALE_P1

    packssdw    xmm3, xmm0              // xmm3=data2=(20 21 22 23 24 25 26 27)
    packssdw    xmm5, xmm6              // xmm5=data5=(50 51 52 53 54 55 56 57)

    movdqa      xmm1, wk2   // xmm1=tmp13L
    movdqa      xmm4, wk3   // xmm4=tmp13H
    movdqa      xmm2, wk8   // xmm2=tmp0L
    movdqa      xmm7, wk9   // xmm7=tmp0H

    movdqa      xmm0, xmm1
    movdqa      xmm6, xmm4
    paddd       xmm1, xmm2              // xmm1=data3L
    paddd       xmm4, xmm7              // xmm4=data3H
    psubd       xmm0, xmm2              // xmm0=data4L
    psubd       xmm6, xmm7              // xmm6=data4H

    movdqa_c      xmm2, PD_DESCALE_P1 // xmm2=[rel PD_DESCALE_P1]

    paddd       xmm1, xmm2
    paddd       xmm4, xmm2
    psrad       xmm1, DESCALE_P1
    psrad       xmm4, DESCALE_P1
    paddd       xmm0, xmm2
    paddd       xmm6, xmm2
    psrad       xmm0, DESCALE_P1
    psrad       xmm6, DESCALE_P1

    packssdw    xmm1, xmm4              // xmm1=data3=(30 31 32 33 34 35 36 37)
    packssdw    xmm0, xmm6              // xmm0=data4=(40 41 42 43 44 45 46 47)

    movdqa      xmm7, wk0   // xmm7=(00 10 01 11 02 12 03 13)
    movdqa      xmm2, wk1   // xmm2=(04 14 05 15 06 16 07 17)

    movdqa      xmm4, xmm3              // transpose coefficients(phase 1)
    punpcklwd   xmm3, xmm1              // xmm3=(20 30 21 31 22 32 23 33)
    punpckhwd   xmm4, xmm1              // xmm4=(24 34 25 35 26 36 27 37)
    movdqa      xmm6, xmm0              // transpose coefficients(phase 1)
    punpcklwd   xmm0, xmm5              // xmm0=(40 50 41 51 42 52 43 53)
    punpckhwd   xmm6, xmm5              // xmm6=(44 54 45 55 46 56 47 57)

    movdqa      xmm1, xmm7              // transpose coefficients(phase 2)
    punpckldq   xmm7, xmm3              // xmm7=(00 10 20 30 01 11 21 31)
    punpckhdq   xmm1, xmm3              // xmm1=(02 12 22 32 03 13 23 33)
    movdqa      xmm5, xmm2              // transpose coefficients(phase 2)
    punpckldq   xmm2, xmm4              // xmm2=(04 14 24 34 05 15 25 35)
    punpckhdq   xmm5, xmm4              // xmm5=(06 16 26 36 07 17 27 37)

    movdqa      xmm3, wk4   // xmm3=(60 70 61 71 62 72 63 73)
    movdqa      xmm4, wk5   // xmm4=(64 74 65 75 66 76 67 77)

    movdqa      wk6, xmm2   // wk(6)=(04 14 24 34 05 15 25 35)
    movdqa      wk7, xmm5   // wk(7)=(06 16 26 36 07 17 27 37)

    movdqa      xmm2, xmm0              // transpose coefficients(phase 2)
    punpckldq   xmm0, xmm3              // xmm0=(40 50 60 70 41 51 61 71)
    punpckhdq   xmm2, xmm3              // xmm2=(42 52 62 72 43 53 63 73)
    movdqa      xmm5, xmm6              // transpose coefficients(phase 2)
    punpckldq   xmm6, xmm4              // xmm6=(44 54 64 74 45 55 65 75)
    punpckhdq   xmm5, xmm4              // xmm5=(46 56 66 76 47 57 67 77)

    movdqa      xmm3, xmm7              // transpose coefficients(phase 3)
    punpcklqdq  xmm7, xmm0              // xmm7=col0=(00 10 20 30 40 50 60 70)
    punpckhqdq  xmm3, xmm0              // xmm3=col1=(01 11 21 31 41 51 61 71)
    movdqa      xmm4, xmm1              // transpose coefficients(phase 3)
    punpcklqdq  xmm1, xmm2              // xmm1=col2=(02 12 22 32 42 52 62 72)
    punpckhqdq  xmm4, xmm2              // xmm4=col3=(03 13 23 33 43 53 63 73)

    movdqa      xmm0, wk6   // xmm0=(04 14 24 34 05 15 25 35)
    movdqa      xmm2, wk7   // xmm2=(06 16 26 36 07 17 27 37)

    movdqa      wk8, xmm3   // wk(8)=col1
    movdqa      wk9, xmm4   // wk(9)=col3

    movdqa      xmm3, xmm0              // transpose coefficients(phase 3)
    punpcklqdq  xmm0, xmm6              // xmm0=col4=(04 14 24 34 44 54 64 74)
    punpckhqdq  xmm3, xmm6              // xmm3=col5=(05 15 25 35 45 55 65 75)
    movdqa      xmm4, xmm2              // transpose coefficients(phase 3)
    punpcklqdq  xmm2, xmm5              // xmm2=col6=(06 16 26 36 46 56 66 76)
    punpckhqdq  xmm4, xmm5              // xmm4=col7=(07 17 27 37 47 57 67 77)

    movdqa      wk10, xmm3  // wk(10)=col5
    movdqa      wk11, xmm4  // wk(11)=col7

    end_block // .column_end:

    // ---- Pass 2: process rows from work array, store into output array.

    // -- Even part

    // xmm7=col0, xmm1=col2, xmm0=col4, xmm2=col6

    // (Original)
    // z1 = (z2 + z3) * 0.541196100;
    // tmp2 = z1 + z3 * -1.847759065;
    // tmp3 = z1 + z2 * 0.765366865;
    //
    // (This implementation)
    // tmp2 = z2 * 0.541196100 + z3 * (0.541196100 - 1.847759065);
    // tmp3 = z2 * (0.541196100 + 0.765366865) + z3 * 0.541196100;

    movdqa      xmm6, xmm1              // xmm1=in2=z2
    movdqa      xmm5, xmm1
    punpcklwd   xmm6, xmm2              // xmm2=in6=z3
    punpckhwd   xmm5, xmm2
    movdqa      xmm1, xmm6
    movdqa      xmm2, xmm5
    pmaddwd     xmm6, V128_PW_F130_F054   // xmm6=tmp3L
    pmaddwd     xmm5, V128_PW_F130_F054   // xmm5=tmp3H
    pmaddwd     xmm1, V128_PW_F054_MF130  // xmm1=tmp2L
    pmaddwd     xmm2, V128_PW_F054_MF130  // xmm2=tmp2H

    movdqa      xmm3, xmm7
    paddw       xmm7, xmm0              // xmm7=in0+in4
    psubw       xmm3, xmm0              // xmm3=in0-in4

    pxor        xmm4, xmm4
    pxor        xmm0, xmm0
    punpcklwd   xmm4, xmm7              // xmm4=tmp0L
    punpckhwd   xmm0, xmm7              // xmm0=tmp0H
    psrad       xmm4, C16_MCONST_BITS   // psrad xmm4,16 & pslld xmm4,CONST_BITS
    psrad       xmm0, C16_MCONST_BITS   // psrad xmm0,16 & pslld xmm0,CONST_BITS

    movdqa      xmm7, xmm4
    paddd       xmm4, xmm6              // xmm4=tmp10L
    psubd       xmm7, xmm6              // xmm7=tmp13L
    movdqa      xmm6, xmm0
    paddd       xmm0, xmm5              // xmm0=tmp10H
    psubd       xmm6, xmm5              // xmm6=tmp13H

    movdqa      wk0, xmm4   // wk(0)=tmp10L
    movdqa      wk1, xmm0   // wk(1)=tmp10H
    movdqa      wk2, xmm7   // wk(2)=tmp13L
    movdqa      wk3, xmm6   // wk(3)=tmp13H

    pxor        xmm5, xmm5
    pxor        xmm4, xmm4
    punpcklwd   xmm5, xmm3              // xmm5=tmp1L
    punpckhwd   xmm4, xmm3              // xmm4=tmp1H
    psrad       xmm5, C16_MCONST_BITS   // psrad xmm5,16 & pslld xmm5,CONST_BITS
    psrad       xmm4, C16_MCONST_BITS   // psrad xmm4,16 & pslld xmm4,CONST_BITS

    movdqa      xmm0, xmm5
    paddd       xmm5, xmm1              // xmm5=tmp11L
    psubd       xmm0, xmm1              // xmm0=tmp12L
    movdqa      xmm7, xmm4
    paddd       xmm4, xmm2              // xmm4=tmp11H
    psubd       xmm7, xmm2              // xmm7=tmp12H

    movdqa      wk4, xmm5   // wk(4)=tmp11L
    movdqa      wk5, xmm4   // wk(5)=tmp11H
    movdqa      wk6, xmm0   // wk(6)=tmp12L
    movdqa      wk7, xmm7   // wk(7)=tmp12H

    // -- Odd part

    movdqa      xmm6, wk9   // xmm6=col3
    movdqa      xmm3, wk8   // xmm3=col1
    movdqa      xmm1, wk11  // xmm1=col7
    movdqa      xmm2, wk10  // xmm2=col5

    movdqa      xmm5, xmm6
    movdqa      xmm4, xmm3
    paddw       xmm5, xmm1              // xmm5=z3
    paddw       xmm4, xmm2              // xmm4=z4

    // (Original)
    // z5 = (z3 + z4) * 1.175875602;
    // z3 = z3 * -1.961570560;  z4 = z4 * -0.390180644;
    // z3 += z5;  z4 += z5;
    //
    // (This implementation)
    // z3 = z3 * (1.175875602 - 1.961570560) + z4 * 1.175875602;
    // z4 = z3 * 1.175875602 + z4 * (1.175875602 - 0.390180644);

    movdqa      xmm0, xmm5
    movdqa      xmm7, xmm5
    punpcklwd   xmm0, xmm4
    punpckhwd   xmm7, xmm4
    movdqa      xmm5, xmm0
    movdqa      xmm4, xmm7
    pmaddwd     xmm0, V128_PW_MF078_F117  // xmm0=z3L
    pmaddwd     xmm7, V128_PW_MF078_F117  // xmm7=z3H
    pmaddwd     xmm5, V128_PW_F117_F078   // xmm5=z4L
    pmaddwd     xmm4, V128_PW_F117_F078   // xmm4=z4H

    movdqa      wk10, xmm0  // wk(10)=z3L
    movdqa      wk11, xmm7  // wk(11)=z3H

    // (Original)
    // z1 = tmp0 + tmp3;  z2 = tmp1 + tmp2;
    // tmp0 = tmp0 * 0.298631336;  tmp1 = tmp1 * 2.053119869;
    // tmp2 = tmp2 * 3.072711026;  tmp3 = tmp3 * 1.501321110;
    // z1 = z1 * -0.899976223;  z2 = z2 * -2.562915447;
    // tmp0 += z1 + z3;  tmp1 += z2 + z4;
    // tmp2 += z2 + z3;  tmp3 += z1 + z4;
    //
    // (This implementation)
    // tmp0 = tmp0 * (0.298631336 - 0.899976223) + tmp3 * -0.899976223;
    // tmp1 = tmp1 * (2.053119869 - 2.562915447) + tmp2 * -2.562915447;
    // tmp2 = tmp1 * -2.562915447 + tmp2 * (3.072711026 - 2.562915447);
    // tmp3 = tmp0 * -0.899976223 + tmp3 * (1.501321110 - 0.899976223);
    // tmp0 += z3;  tmp1 += z4;
    // tmp2 += z3;  tmp3 += z4;

    movdqa      xmm0, xmm1
    movdqa      xmm7, xmm1
    punpcklwd   xmm0, xmm3
    punpckhwd   xmm7, xmm3
    movdqa      xmm1, xmm0
    movdqa      xmm3, xmm7
    pmaddwd     xmm0, V128_PW_MF060_MF089  // xmm0=tmp0L
    pmaddwd     xmm7, V128_PW_MF060_MF089  // xmm7=tmp0H
    pmaddwd     xmm1, V128_PW_MF089_F060   // xmm1=tmp3L
    pmaddwd     xmm3, V128_PW_MF089_F060   // xmm3=tmp3H

    paddd       xmm0, wk10  // xmm0=tmp0L
    paddd       xmm7, wk11  // xmm7=tmp0H
    paddd       xmm1, xmm5              // xmm1=tmp3L
    paddd       xmm3, xmm4              // xmm3=tmp3H

    movdqa      wk8, xmm0   // wk(8)=tmp0L
    movdqa      wk9, xmm7   // wk(9)=tmp0H

    movdqa      xmm0, xmm2
    movdqa      xmm7, xmm2
    punpcklwd   xmm0, xmm6
    punpckhwd   xmm7, xmm6
    movdqa      xmm2, xmm0
    movdqa      xmm6, xmm7
    pmaddwd     xmm0, V128_PW_MF050_MF256  // xmm0=tmp1L
    pmaddwd     xmm7, V128_PW_MF050_MF256  // xmm7=tmp1H
    pmaddwd     xmm2, V128_PW_MF256_F050   // xmm2=tmp2L
    pmaddwd     xmm6, V128_PW_MF256_F050   // xmm6=tmp2H

    paddd       xmm0, xmm5              // xmm0=tmp1L
    paddd       xmm7, xmm4              // xmm7=tmp1H
    paddd       xmm2, wk10  // xmm2=tmp2L
    paddd       xmm6, wk11  // xmm6=tmp2H

    movdqa      wk10, xmm0  // wk(10)=tmp1L
    movdqa      wk11, xmm7  // wk(11)=tmp1H

    // -- Final output stage

    movdqa      xmm5, wk0   // xmm5=tmp10L
    movdqa      xmm4, wk1   // xmm4=tmp10H

    movdqa      xmm0, xmm5
    movdqa      xmm7, xmm4
    paddd       xmm5, xmm1              // xmm5=data0L
    paddd       xmm4, xmm3              // xmm4=data0H
    psubd       xmm0, xmm1              // xmm0=data7L
    psubd       xmm7, xmm3              // xmm7=data7H

    movdqa_c      xmm1, PD_DESCALE_P2 // xmm1=[rel PD_DESCALE_P2]

    paddd       xmm5, xmm1
    paddd       xmm4, xmm1
    psrad       xmm5, DESCALE_P2
    psrad       xmm4, DESCALE_P2
    paddd       xmm0, xmm1
    paddd       xmm7, xmm1
    psrad       xmm0, DESCALE_P2
    psrad       xmm7, DESCALE_P2

    packssdw    xmm5, xmm4              // xmm5=data0=(00 10 20 30 40 50 60 70)
    packssdw    xmm0, xmm7              // xmm0=data7=(07 17 27 37 47 57 67 77)

    movdqa      xmm3, wk4   // xmm3=tmp11L
    movdqa      xmm1, wk5   // xmm1=tmp11H

    movdqa      xmm4, xmm3
    movdqa      xmm7, xmm1
    paddd       xmm3, xmm2              // xmm3=data1L
    paddd       xmm1, xmm6              // xmm1=data1H
    psubd       xmm4, xmm2              // xmm4=data6L
    psubd       xmm7, xmm6              // xmm7=data6H

    movdqa_c      xmm2, PD_DESCALE_P2 // xmm2=[rel PD_DESCALE_P2]

    paddd       xmm3, xmm2
    paddd       xmm1, xmm2
    psrad       xmm3, DESCALE_P2
    psrad       xmm1, DESCALE_P2
    paddd       xmm4, xmm2
    paddd       xmm7, xmm2
    psrad       xmm4, DESCALE_P2
    psrad       xmm7, DESCALE_P2

    packssdw    xmm3, xmm1              // xmm3=data1=(01 11 21 31 41 51 61 71)
    packssdw    xmm4, xmm7              // xmm4=data6=(06 16 26 36 46 56 66 76)

    packsswb    xmm5, xmm4              // xmm5=(00 10 20 30 40 50 60 70 06 16 26 36 46 56 66 76)
    packsswb    xmm3, xmm0              // xmm3=(01 11 21 31 41 51 61 71 07 17 27 37 47 57 67 77)

    movdqa      xmm6, wk6   // xmm6=tmp12L
    movdqa      xmm2, wk7   // xmm2=tmp12H
    movdqa      xmm1, wk10  // xmm1=tmp1L
    movdqa      xmm7, wk11  // xmm7=tmp1H

    movdqa      wk0, xmm5   // wk(0)=(00 10 20 30 40 50 60 70 06 16 26 36 46 56 66 76)
    movdqa      wk1, xmm3   // wk(1)=(01 11 21 31 41 51 61 71 07 17 27 37 47 57 67 77)

    movdqa      xmm4, xmm6
    movdqa      xmm0, xmm2
    paddd       xmm6, xmm1              // xmm6=data2L
    paddd       xmm2, xmm7              // xmm2=data2H
    psubd       xmm4, xmm1              // xmm4=data5L
    psubd       xmm0, xmm7              // xmm0=data5H

    movdqa_c      xmm5, PD_DESCALE_P2 // xmm5=[rel PD_DESCALE_P2]

    paddd       xmm6, xmm5
    paddd       xmm2, xmm5
    psrad       xmm6, DESCALE_P2
    psrad       xmm2, DESCALE_P2
    paddd       xmm4, xmm5
    paddd       xmm0, xmm5
    psrad       xmm4, DESCALE_P2
    psrad       xmm0, DESCALE_P2

    packssdw    xmm6, xmm2              // xmm6=data2=(02 12 22 32 42 52 62 72)
    packssdw    xmm4, xmm0              // xmm4=data5=(05 15 25 35 45 55 65 75)

    movdqa      xmm3, wk2   // xmm3=tmp13L
    movdqa      xmm1, wk3   // xmm1=tmp13H
    movdqa      xmm7, wk8   // xmm7=tmp0L
    movdqa      xmm5, wk9   // xmm5=tmp0H

    movdqa      xmm2, xmm3
    movdqa      xmm0, xmm1
    paddd       xmm3, xmm7              // xmm3=data3L
    paddd       xmm1, xmm5              // xmm1=data3H
    psubd       xmm2, xmm7              // xmm2=data4L
    psubd       xmm0, xmm5              // xmm0=data4H

    movdqa_c      xmm7, PD_DESCALE_P2 // xmm7=[rel PD_DESCALE_P2]

    paddd       xmm3, xmm7
    paddd       xmm1, xmm7
    psrad       xmm3, DESCALE_P2
    psrad       xmm1, DESCALE_P2
    paddd       xmm2, xmm7
    paddd       xmm0, xmm7
    psrad       xmm2, DESCALE_P2
    psrad       xmm0, DESCALE_P2

    //movdqa      xmm5, [rel PB_CENTERJSAMP]  ; xmm5=[rel PB_CENTERJSAMP]
    i32.const   CENTERJSAMPLE
    i8x16.splat
    local.set   xmm5

    packssdw    xmm3, xmm1             // xmm3=data3=(03 13 23 33 43 53 63 73)
    packssdw    xmm2, xmm0             // xmm2=data4=(04 14 24 34 44 54 64 74)

    movdqa      xmm7, wk0  // xmm7=(00 10 20 30 40 50 60 70 06 16 26 36 46 56 66 76)
    movdqa      xmm1, wk1  // xmm1=(01 11 21 31 41 51 61 71 07 17 27 37 47 57 67 77)

    packsswb    xmm6, xmm2             // xmm6=(02 12 22 32 42 52 62 72 04 14 24 34 44 54 64 74)
    packsswb    xmm3, xmm4             // xmm3=(03 13 23 33 43 53 63 73 05 15 25 35 45 55 65 75)

    paddb       xmm7, xmm5
    paddb       xmm1, xmm5
    paddb       xmm6, xmm5
    paddb       xmm3, xmm5

    movdqa      xmm0, xmm7        // transpose coefficients(phase 1)
    punpcklbw   xmm7, xmm1        // xmm7=(00 01 10 11 20 21 30 31 40 41 50 51 60 61 70 71)
    punpckhbw   xmm0, xmm1        // xmm0=(06 07 16 17 26 27 36 37 46 47 56 57 66 67 76 77)
    movdqa      xmm2, xmm6        // transpose coefficients(phase 1)
    punpcklbw   xmm6, xmm3        // xmm6=(02 03 12 13 22 23 32 33 42 43 52 53 62 63 72 73)
    punpckhbw   xmm2, xmm3        // xmm2=(04 05 14 15 24 25 34 35 44 45 54 55 64 65 74 75)

    movdqa      xmm4, xmm7        // transpose coefficients(phase 2)
    punpcklwd   xmm7, xmm6        // xmm7=(00 01 02 03 10 11 12 13 20 21 22 23 30 31 32 33)
    punpckhwd   xmm4, xmm6        // xmm4=(40 41 42 43 50 51 52 53 60 61 62 63 70 71 72 73)
    movdqa      xmm5, xmm2        // transpose coefficients(phase 2)
    punpcklwd   xmm2, xmm0        // xmm2=(04 05 06 07 14 15 16 17 24 25 26 27 34 35 36 37)
    punpckhwd   xmm5, xmm0        // xmm5=(44 45 46 47 54 55 56 57 64 65 66 67 74 75 76 77)

    movdqa      xmm1, xmm7        // transpose coefficients(phase 3)
    punpckldq   xmm7, xmm2        // xmm7=(00 01 02 03 04 05 06 07 10 11 12 13 14 15 16 17)
    punpckhdq   xmm1, xmm2        // xmm1=(20 21 22 23 24 25 26 27 30 31 32 33 34 35 36 37)
    movdqa      xmm3, xmm4        // transpose coefficients(phase 3)
    punpckldq   xmm4, xmm5        // xmm4=(40 41 42 43 44 45 46 47 50 51 52 53 54 55 56 57)
    punpckhdq   xmm3, xmm5        // xmm3=(60 61 62 63 64 65 66 67 70 71 72 73 74 75 76 77)

    pshufd_4e      xmm6, xmm7 // 0x4E  ; xmm6=(10 11 12 13 14 15 16 17 00 01 02 03 04 05 06 07)
    pshufd_4e      xmm0, xmm1 // 0x4E  ; xmm0=(30 31 32 33 34 35 36 37 20 21 22 23 24 25 26 27)
    pshufd_4e      xmm2, xmm4 // 0x4E  ; xmm2=(50 51 52 53 54 55 56 57 40 41 42 43 44 45 46 47)
    pshufd_4e      xmm5, xmm3 // 0x4E  ; xmm5=(70 71 72 73 74 75 76 77 60 61 62 63 64 65 66 67)
   
    store_row_mm 0, xmm7
    store_row_mm 8, xmm1
    store_row_mm 16, xmm4
    store_row_mm 24, xmm3

    store_row_mm 4, xmm6
    store_row_mm 12, xmm0
    store_row_mm 20, xmm2
    store_row_mm 28, xmm5

    i32.const 0
    end_function

asm_function jsimd_extrgb_ycc_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function

asm_function jsimd_ycc_extrgb_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function

asm_function jsimd_ycc_rgb565_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function

asm_function jsimd_h2v1_fancy_upsample_wasm (i32,i32,i32,i32) (i32)
    unreachable
    end_function

asm_function jsimd_idct_2x2_wasm (i32,i32,i32,i32) (i32)
    unreachable
    end_function

asm_function jsimd_idct_4x4_wasm (i32,i32,i32,i32) (i32)
    unreachable
    end_function

asm_function jsimd_idct_ifast_wasm (i32,i32,i32,i32) (i32)
    unreachable
    end_function

asm_function jsimd_ycc_extrgbx_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function

asm_function jsimd_ycc_extbgr_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function

asm_function jsimd_ycc_extbgrx_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function

asm_function jsimd_ycc_extxbgr_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function

asm_function jsimd_ycc_extxrgb_convert_wasm (i32,i32,i32,i32,i32) ()
    unreachable
    end_function


.globaltype __stack_pointer, i32
