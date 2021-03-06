

; SERIAL I/O
TTI	EQU	$20
TTO	EQU	$20
TTS	EQU	$25
TTYDA	EQU	$01
TTYTR	EQU	$20


  

;CONSTANTS

CTRX	EQU	$24	; CONTROLX
CR	EQU	$0D
SOH	EQU	1	; Start of Header
ACK     EQU     06H     ; Acknowledge
NAK     EQU     15H     ; Negative acknowledge
EOF     EQU     1AH     ; End of file - ^Z
EOT     EQU     04H     ; End of transmission
ERRLIM	EQU	10	; Max allowable errors


**********************************************************

REST	EQU	$0
DEV_SW	EQU	$50
FILL_VRAM	EQU	$18D4
VIDEO_INIT	EQU	$18E9
FONT_INIT	EQU	$1927
WRTRGV	EQU	$1FD9
RCOPYV	EQU	$1FBE
COLOR_TAB	EQU	$143B

CARTADD	EQU	$8000



*
*	XMODEM 38400,8,N,1
*

	ORG	$7400  * For 2K ram start at 1K=$7000-73ff ; 2k=$7400 - 7800 
			*// hex2bin need offset of 0x0200 for the hex file //Bios is set top jmp 0x7200
*	ORG     $2000  * ROM BASED AT 0X2000
	IN	DEV_SW
	ANI	$01
	JZ	$006E

	LXI	H,0000
	LXI	D,$4000
        CALL	FILL_VRAM
        CALL	VIDEO_INIT
        CALL    FONT_INIT

	LXI	H,MSG
	LXI	D,$01E2
	DB	$FD,$21 * LD IY,
	DW      28      *       LENGTH
	MVI	A,2
	CALL	RCOPYV

	LXI	H,COLOR_TAB
        LXI	D,0000
	MVI	A,4
	DB	$FD,$21  * LD IY,
	DW	$0012    *       LENGTH
	CALL	RCOPYV        

	MVI	B,1
	MVI	C,$C0
	CALL	WRTRGV

;INIT UART	
	MVI A,0     * INT OFF
        OUT $21
        MVI A,$80
        OUT $23       * DLAB
        MVI A,$23 *38400  * 19200 = $46     *$8b   * div hi 21400000/(139*16)=9600     *6500000/(42 * 16)=9600 -use 42
        OUT $20       
        MVI A,0      * div lo
        OUT $21
        MVI A,3      * 8,n,1
        OUT $23
        MVI A,$0B    *TURN ON DTR,RTS,OUT2
        OUT $24


;---------------------
; XMODEM receive routine
;---------------------
; Implements basic XMODEM checksum receive function to allow loading larger
; files from PC with fewer errors.  Code modified from XMODEM v3.2 source
; by Keith Petersen
XMODEM:
        LXI	H,CARTADD
	SHLD	DEST	;save destination address
	;MVI	A,0	; Initialize sector number to zero
	XRA	A
	STA	SECTNO	;
	
RCVLP:	
	CALL	RCVSECT	;GET A SECTOR
	JC	RCVEOT	;GOT EOT?
	CALL	WRSECT	;WRITE THE SECTOR
	CALL	INCRSNO	;BUMP SECTOR #
	CALL	SENDACK	;ACK THE SECTOR
	JMP	RCVLP	;LOOP UNTIL EOF
;
;GOT EOT ON SECTOR - FLUSH BUFFERS, END
;
RCVEOT:	
		
	CALL	SENDACK	;ACK THE SECTOR
	MVI	A,'G'
	CALL	SEND		
	JMP	REST




;**** XMODEM SUBROUTINES		
;
;---->	RCVSECT: RECEIVE A SECTOR
;
;RETURNS WITH CARRY SET IF EOT RECEIVED.
;
RCVSECT:
	XRA	A	;GET 0
	STA	ERRCT	;INIT ERROR COUNT
;
RCVRPT:	
	MVI	B,10	;10 SEC TIMEOUT
	CALL	RECV	;GET SOH/EOT
	JC	RCVSTOT	;TIMEOUT
	CPI	SOH	;GET SOH?
	JZ	RCVSOH	;..YES
;
;EARLIER VERS. OF MODEM PROG SENT SOME NULLS -
;IGNORE THEM
;
	ORA	A	;00 FROM SPEED CHECK?
	JZ	RCVRPT	;YES, IGNORE IT
	CPI	EOT	;END OF TRANSFER?
	STC		;RETURN WITH CARRY..
	RZ		;..SET IF EOT
;
;DIDN'T GET SOH  OR EOT - 
;
;DIDN'T GET VALID HEADER - PURGE THE LINE,
;THEN SEND NAK.
;
RCVSERR:
	MVI	B,1	;WAIT FOR 1 SEC..
	CALL	RECV	;..WITH NO CHARS
	JNC	RCVSERR	;LOOP UNTIL SENDER DONE
	MVI	A,NAK	;SEND..
	CALL	SEND	;..THE NAK
	LDA	ERRCT	;ABORT IF..
	INR	A	;..WE HAVE REACHED..
	STA	ERRCT	;..THE ERROR..
	CPI	ERRLIM	;..LIMIT?
	JC	RCVRPT	;..NO, TRY AGAIN
;
;10 ERRORS IN A ROW - 
;
RCVSABT:
;	CALL	ILPRT
;	DB	'++UNABLE TO RECEIVE BLOCK '
;	DB	'- ABORTING++',CR,0

	MVI	A,'E'
	CALL	SEND
	JMP	REST    ;JUMP TO RESET

;
;TIMEDOUT ON RECEIVE
;
RCVSTOT:
	JMP	RCVSERR	;BUMP ERR CT, ETC.
;
;GOT SOH - GET BLOCK #, BLOCK # COMPLEMENTED
;
RCVSOH:
	MVI	B,1	;TIMEOUT = 1 SEC
	CALL	RECV	;GET SECTOR
	JC	RCVSTOT	;GOT TIMEOUT
	MOV	D,A	;D=BLK #
	MVI	B,1	;TIMEOUT = 1 SEC
	CALL	RECV	;GET CMA'D SECT #
	JC	RCVSTOT	;TIMEOUT
	CMA		;CALC COMPLEMENT
	CMP	D	;GOOD SECTOR #?
	JZ	RCVDATA	;YES, GET DATA
;
;GOT BAD SECTOR #
;
	JMP	RCVSERR	;BUMP ERROR CT.
;
RCVDATA:
	MOV	A,D	;GET SECTOR #
	STA	RCVSNO	;SAVE IT
	MVI	C,0	;INIT CKSUM
	LXI	H,DMABUF ;POINT TO BUFFER  
;
RCVCHR:
	MVI	B,1	;1 SEC TIMEOUT
	CALL	RECV	;GET CHAR
	JC	RCVSTOT	;TIMEOUT
	MOV	M,A	;STORE CHAR
	INR	L	;DONE?
	JNZ	RCVCHR	;NO, LOOP
;
;VERIFY CHECKSUM
;
	MOV	D,C	;SAVE CHECKSUM
	MVI	B,1	;TIMEOUT LEN.
	CALL	RECV	;GET CHECKSUM
	JC	RCVSTOT	;TIMEOUT
	CMP	D	;CHECKSUM OK?
	JNZ	RCVSERR	;NO, ERROR
;
;GOT A SECTOR, IT'S A DUP IF = PREV,
;	OR OK IF = 1 + PREV SECTOR
;
	LDA	RCVSNO	;GET RECEIVED
	MOV	B,A	;SAVE IT
	LDA	SECTNO	;GET PREV
	CMP	B	;PREV REPEATED?
	JZ	RECVACK	;ACK TO CATCH UP
	INR	A	;CALC NEXT SECTOR #
	CMP	B	;MATCH?
	JNZ	ABORT	;NO MATCH - STOP SENDER, EXIT
	RET		;CARRY OFF - NO ERRORS
;
;PREV SECT REPEATED, DUE TO THE LAST ACK
;BEING GARBAGED.  ACK IT SO SENDER WILL CATCH UP 
;
RECVACK:
	CALL	SENDACK	;SEND THE ACK,
	JMP	RCVSECT	;GET NEXT BLOCK
;
;SEND AN ACK FOR THE SECTOR
;
SENDACK:
	MVI	A,ACK	;GET ACK
	CALL	SEND	;..AND SEND IT
	RET
;	

ABORT:
	;LXI	SP,STACK
;
ABORTL:
	MVI	B,1	;1 SEC. W/O CHARS.
	CALL	RECV
	JNC	ABORTL	;LOOP UNTIL SENDER DONE
	MVI	A,CTRX	;CONTROL X
	CALL	SEND	;STOP SENDING END
;
ABORTW:
	MVI	B,1	;1 SEC W/O CHARS.
	CALL	RECV
	JNC	ABORTW	;LOOP UNTIL SENDER DONE
	MVI	A,' '	;GET A SPACE...
	CALL	SEND	;TO CLEAR OUT CONTROL X

;	MVI	A,'X'
;	CALL	SEND
	JMP	REST

;	CALL	ILPRT
;	DB	CR,'XMODEM CANCELLED',CR,'0'
;	RET		; <--------exit point -------

;
;---->	INCRSNO: INCREMENT SECTOR #
;
INCRSNO:
	LDA	SECTNO	;INCR..
	INR	A	;..SECT..
	STA	SECTNO	;..NUMBER
	RET
;

;
;---->	WRSECT: WRITE A SECTOR
;
WRSECT:
	LHLD	DEST		;load destination address to HL
	XCHG			;put destination address in DE
	LXI	H,DMABUF	;load CPM dma buffer address to HL
	LXI	B,$0080
	DB	$ED ;LDIR
	DB	$B0
	XCHG
	SHLD	DEST
	RET

;	LHLD	DEST		;load destination address to HL
;	XCHG			;put destination address in DE
;	LXI	H,DMABUF	;load CPM dma buffer address to HL
;	CALL	MOVE128		;move 128 bytes to destination
;	XCHG			; get updated dest addr in HL
;	SHLD	DEST		; store it - update destination pointer
;	RET

;
;---->	RECV: RECEIVE A CHARACTER
;
;TIMEOUT TIME IS IN B, IN SECONDS.  
;
RECV:
	PUSH	D	;SAVE
;
	;IF	FASTCLK	;4MHZ?
	;MOV	A,B	;GET TIME REQUEST
	;ADD	A	;DOUBLE IT
	;MOV	B,A	;NEW TIME IN B
	;ENDIF
;
MSEC:
	LXI	D,7150  ;50000	;1 SEC DCR COUNT
;
MWTI:
    	IN      TTS		; IMSAI specific, check input status
    	ANI     TTYDA	; ""
    	JNZ	MCHAR	;got a char
    
	DCR	E	;COUNT..
	JNZ	MWTI	;..DOWN..
	DCR	D	;..FOR..
	JNZ	MWTI	;..TIMEOUT
	DCR	B	;MORE SECONDS?
	JNZ	MSEC	;YES, WAIT
;
;MODEM TIMED OUT RECEIVING
;
	POP	D	;RESTORE D,E
	STC		;CARRY SHOWS TIMEOUT
	RET
;
;GOT CHAR FROM MODEM
;
MCHAR:
    	IN      TTI	; IMSAI specific, get input byte
	POP	D	;RESTORE DE
;
;CALC CHECKSUM
;
	PUSH	PSW	;SAVE THE CHAR
	ADD	C	;ADD TO CHECKSUM
	MOV	C,A	;SAVE CHECKSUM
	POP	PSW	;RESTORE CHAR
	ORA	A	;CARRY OFF: NO ERROR
	RET		;FROM "RECV"
;
;
;---->	SEND: SEND A CHARACTER TO THE MODEM
;
SEND:
	PUSH	PSW	;SAVE THE CHAR
;	ADD	C	;CALC CKSUM    WHY ? LAK
;	MOV	C,A	;SAVE CKSUM    WHY ? LAK

SENDW:
	IN	TTS	; IMSAI specific, Check Console Output Status
    	ANI	TTYTR 
	JZ	SENDW	;..NO, WAIT
	POP	PSW	;GET CHAR
    	OUT	TTO     ; IMSAI specific, Send Data
	RET		;FROM "SEND"

;
;----->  MOVE 128 CHARACTERS
;
;MOVE128:
;	MVI	B,128	;SET MOVE COUNT
;
;MOVE FROM (HL) TO (DE) LENGTH IN (B)
;
;MOVE:
;	MOV	A,M	;GET A CHAR
;	STAX	D	;STORE IT
;	INX	H	;TO NEXT "FROM"
;	INX	D	;TO NEXT "TO"
;	DCR	B	;MORE?
;	JNZ	MOVE	;..YES, LOOP
;	RET		;..NO, RETURN


;
	ORG	$7580

DMABUF	DS	128
      
MSG	STR	"XMODEM RECEIVE (38400,8,N,1)"


RCVSNO	DB	1	; SECT # RECEIVED (XMODEM)
SECTNO	DB	1	; CURRENT SECTOR NUMBER (XMODEM)
ERRCT	DB	1	; ERROR COUNT(XMODEM)
DEST	DW	1	; destination address pointer 2BYTES (XMODEM)  
