'================================================
' CHUONG TRINH ROBONOVA-II (MR-C3024FX) TICH HOP CAM BIEN CHO ROBOT MINA
' Ke thua day du 63 dong tac goc (K1..K68) & bo sung:
'   1. Cam bien sieu am tren mat: SONAR(5) -> Chan #10 (Trigger) & #11 (Echo) tren cum G6B
'      (Hoac doi CONST US_USE_AD = 1 neu dung sieu am Analog 3 chan tren AD1)
'   2. Cam bien khoang cach 10k: Analog AD(0) tren cum AD0..AD7
'   3. Cam bien dien ap Pin: AD(6) | Cam bien nghieng/nga: AD(5)
'   4. Giao tiep UART 2 chieu 9600 baud voi Board Android A33 (ERX nhan lenh, ETX gui 8 byte cam bien)
'
' RR : internal parameter variable / ROBOREMOCON / Action command
' A  : temporary variable          / REMOCON
' A16,A26 : temporary variable
'
'== auto_main ===================================
GOTO AUTO
FILL 255,10000

DIM RR AS BYTE
DIM A AS BYTE
DIM A16 AS BYTE
DIM A26 AS BYTE
DIM BTOut AS BYTE ' RS-232 output on ETX (9600 baud -> Android RX)
DIM BT AS BYTE    ' RS-232 input on ERX (9600 baud <- Android TX)

' --- Bien cam bien & truyen thong Mina AI ---
DIM US_RAW AS INTEGER
DIM IDLE_TICK AS INTEGER
DIM CHK_SUM AS INTEGER
DIM US_HI AS BYTE
DIM US_LO AS BYTE
DIM DIST_10K AS BYTE
DIM BATT_RAW AS BYTE
DIM TILT_RAW AS BYTE
DIM CHK_BYTE AS BYTE
DIM RFX_ON AS BYTE
DIM OBS_HIT AS BYTE

CONST ID = 0             ' 1:0, 2:32, 3:64, 4:96
CONST US_PORT = 5     ' SONAR(5): Port #10 = Trigger, Port #11 = Echo (G6B)
CONST US_USE_AD = 0   ' 0 = Digital SONAR(5) | 1 = Analog AD(US_AD_PORT)
CONST US_AD_PORT = 1  ' Kenh AD du phong neu US_USE_AD = 1
CONST DIST_AD_PORT = 0   ' Cam bien do khoang cach 10k tren chan AD(0)
CONST US_LIMIT = 25   ' Nguong vat can sieu am < 25 cm
CONST DIST10K_LIMIT = 85 ' Nguong vat can cam bien 10k AD(0) > 85
CONST TILT_ON = 0       ' 1 = Bat tu dung day theo AD(5) (chi bat khi DA CAM cam bien nghieng)

'== Action command check (50 - 82)
IF RR > 50 AND RR < 83 THEN GOTO action_proc

RR = 0
RFX_ON = 1
IDLE_TICK = 0

PTP SETON
PTP ALLON

'== motor diretion setting ======================
DIR G6A,1,0,0,1,0,0
DIR G6B,1,1,1,1,1,1
DIR G6C,0,0,0,0,0,0
DIR G6D,0,1,1,0,1,0

'== motor start position read ===================
TEMPO 230
MUSIC "CDE"
GETMOTORSET G24,1,1,1,1,1,0,1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,1,1,0
'== motor power on  =============================
SPEED 5
MOTOR G24
GOSUB standard_pose
GOSUB read_and_send_sensors
'================================================

MAIN:
ERX 9600,BT, main_idle
' Ma lenh dieu khien tu Android A33 qua UART 9600:
' - 40..74  -> K1..K35
' - 80..88  -> K40..K48
' - 90..108 -> K50..K68
' - 115 ('s') -> Doc cam bien ngay & gui goi 8 byte [170,85,HI,LO,10K,BATT,TILT,CHK]
' - 109 ('m') -> Bat phan xa phan cung RFX_ON = 1
' - 110 ('n') -> Tat phan xa phan cung RFX_ON = 0
IF BT = 0 THEN GOTO main_idle
IF BT = 115 THEN
	IDLE_TICK = 0
	GOSUB read_and_send_sensors
	GOTO MAIN
ENDIF
IF BT = 109 THEN
	RFX_ON = 1
	IDLE_TICK = 0
	GOSUB read_and_send_sensors
	GOTO MAIN
ENDIF
IF BT = 110 THEN
	RFX_ON = 0
	IDLE_TICK = 0
	GOSUB read_and_send_sensors
	GOTO MAIN
ENDIF
IF BT > 39 AND BT < 75 THEN GOTO MAIN2
IF BT > 79 AND BT < 89 THEN GOTO MAIN3
IF BT > 89 AND BT < 109 THEN GOTO MAIN4
GOTO main_idle

MAIN2:
A = BT - 39
ON A GOTO MAIN,K1,K2,K3,K4,K5,K6,K7,K8,K9,K10,K11,K12,K13,K14,K15,K16,K17,K18,K19,K20,K21,K22,K23,K24,K25,K26,K27,K28,K29,K30,K31,K32,K33,K34,K35
GOTO MAIN
MAIN3:
A = BT - 79
ON A GOTO MAIN,K40,K41,K42,K43,K44,K45,K46,K47,K48
GOTO MAIN
MAIN4:
A = BT - 89
ON A GOTO MAIN,K50,K51,K52,K53,K54,K55,K56,K57,K58,K59,K60,K61,K62,K63,K64,K65,K66,K67,K68
GOTO MAIN

'-----------------------------
main_idle:
A = REMOCON(1)
IF A > ID THEN
	A = A - ID
	ON A GOTO MAIN,K1,K2,K3,K4,K5,K6,K7,K8,K9,K10,K11,K12,K13,K14,K15,K16,K17,K18,K19,K20,K21,K22,K23,K24,K25,K26,K27,K28,K29,K30,K31,K32
ENDIF
IDLE_TICK = IDLE_TICK + 1
IF IDLE_TICK >= 700 THEN
	IDLE_TICK = 0
	GOSUB robot_voltage
	IF RFX_ON = 1 THEN
		GOSUB robot_tilt_auto
	ENDIF
	GOSUB read_and_send_sensors
ENDIF
GOTO MAIN

MAIN1:
GOTO main_idle
'-------------------------------------------------
action_proc:
A = RR - 50
ON A GOTO MAIN,K1,K2,K3,K4,K5,K6,K7,K8,K9,K10,K11,K12,K13,K14,K15,K16,K17,K18,K19,K20,K21,K22,K23,K24,K25,K26,K27,K28,K29,K30,K31,K32
RETURN
'-----------------------------
main_exit:
	IF RR > 50 THEN RETURN
	RR = 0
	IDLE_TICK = 0
	GOSUB read_and_send_sensors
	GOTO MAIN
'================================================
k1:
	GOSUB bow_pose
	GOSUB standard_pose
	GOTO main_exit
k2:
	GOSUB hans_up
	DELAY 500
	GOSUB standard_pose
	GOTO main_exit
k3:
	GOSUB sit_down_pose
	DELAY 1000
	GOSUB standard_pose
	GOTO main_exit
k4:
	GOSUB sit_hans_up
	DELAY 1000
	GOSUB standard_pose
	GOTO main_exit
k5:
	GOSUB foot_up
	GOSUB standard_pose
	GOTO main_exit
k6:
	GOSUB body_move
	GOSUB standard_pose
	GOTO main_exit
k7:
	GOSUB wing_move
	GOSUB standard_pose
	GOTO main_exit
k8:
	GOSUB right_shoot
	GOSUB standard_pose
	DELAY 500
	GOSUB left_shoot
	GOSUB standard_pose	
	DELAY 500
	GOTO main_exit
k9:
	SPEED 8
	GOSUB handstanding
	DELAY 1000
	SPEED 6
	GOSUB standard_pose
	GOTO main_exit
k10:
	IF RFX_ON = 1 THEN
		GOSUB check_front_obstacle
		IF OBS_HIT = 1 THEN
			GOSUB avoid_obstacle_step
			GOTO main_exit
		ENDIF
	ENDIF
	GOSUB fast_walk
	GOSUB standard_pose
	GOTO main_exit
k11:					' ^ 1
	IF RFX_ON = 1 THEN
		GOSUB check_front_obstacle
		IF OBS_HIT = 1 THEN
			GOSUB avoid_obstacle_step
			GOTO main_exit
		ENDIF
	ENDIF
	GOSUB forward_walk
	GOSUB standard_pose
	GOTO main_exit	
k12:					' _ 1
	GOSUB backward_walk
	GOSUB standard_pose
	GOTO main_exit
k13:					' > 1
	SPEED 8
	GOSUB right_shift
	SPEED 6
	GOSUB standard_pose
	GOTO main_exit
k14:					' < 1
	SPEED 8
	GOSUB left_shift
	SPEED 6
	GOSUB standard_pose
	GOTO main_exit
k15:					' A
	GOSUB left_attack
	GOSUB standard_pose
	GOTO main_exit
k16:	
	GOSUB sit_down_pose16
	GOTO main_exit 
	
k17:					' C
	GOSUB left_forward
	GOSUB standard_pose
	GOTO main_exit
k18:					' dac biet
	TEMPO 230
	MUSIC "C"			
	GOTO main_exit
k19:					' P2
	GOSUB backward_standup
	GOSUB standard_pose
	GOTO main_exit
k20:					' B	
	GOSUB right_attack
	GOSUB standard_pose
	GOTO main_exit
k21:					' ^ 2
	GOSUB forward_tumbling
	GOSUB standard_pose	
	GOTO main_exit	
k22:					' *	
	GOSUB left_turn
	GOSUB standard_pose
	GOTO main_exit
k23:					' F
	TEMPO 230
	MUSIC "D"					
	GOTO main_exit
k24:					' #
	GOSUB right_turn
	GOSUB standard_pose	
	GOTO main_exit
k25:					' P1
	GOSUB forward_standup
	GOSUB standard_pose
	GOTO main_exit
k26:					' [] 1	
	GOSUB sit_down_pose26
	GOTO main_exit
k27:					' D
	GOSUB right_forward
	GOSUB standard_pose
	GOTO main_exit	
k28:					' < 2
	GOSUB left_tumbling
	SPEED 10
	GOSUB standard_pose
	GOTO main_exit		
k29:					' [] 2
	GOSUB forward_punch
	SPEED 10
	GOSUB standard_pose
	GOTO main_exit	
k30:					' > 2
	GOSUB righ_tumbling
	SPEED 10
	GOSUB standard_pose
	GOTO main_exit
k31:					' _ 2
	GOSUB back_tumbling
	SPEED 10
	GOSUB standard_pose
	GOTO main_exit
k32:					' G
	TEMPO 230
	MUSIC "E"					
	GOTO main_exit
'================================================ 
' cac dong tac nhanh
k33:                                       
	IF RFX_ON = 1 THEN
		GOSUB check_front_obstacle
		IF OBS_HIT = 1 THEN
			GOSUB avoid_obstacle_step
			GOTO main_exit
		ENDIF
	ENDIF
	GOSUB newfastwalk
	GOSUB standard_pose
	GOTO main_exit
k34:					' *	
	GOSUB fastleftturn
	GOSUB standard_pose
	GOTO main_exit
k35:					' #
	GOSUB fastrightturn
	GOSUB standard_pose	
	GOTO main_exit

'================================================ 
' cac dong tac vo thuat va bo sung
k40:					' dac biet
	TEMPO 230
	MUSIC "C"
        GOSUB pushup	
       GOSUB standard_pose				
	GOTO main_exit
k41:
    GOSUB honor
    DELAY 500
	GOSUB standard_pose
    DELAY 1000
    GOSUB bow_pose
	GOSUB standard_pose
	GOTO main_exit
k42:
	TEMPO 230
	MUSIC "C"
	MUSIC "C"
	MUSIC "E"					
	MUSIC "G"					
    DELAY 150
	MUSIC "E"					
    DELAY 100
	MUSIC "G"					

    GOSUB BigToss
	GOTO main_exit
k43:				

	TEMPO 230
	MUSIC "E"					
   GOSUB BigReach
	GOTO main_exit

k44:
 GOSUB martial_arts_pose2
    DELAY 1000
	GOSUB standard_pose
 GOTO main_exit

k45:
 GOSUB martial_arts_pose3
    DELAY 1000
	GOSUB standard_pose
 GOTO main_exit

k46:					
 GOSUB martial_arts_pose4
    DELAY 1000
	GOSUB standard_pose
 GOTO main_exit

k47:					
 GOSUB martial_arts_pose5
    DELAY 1000
	GOSUB standard_pose
 GOTO main_exit

k48:					
 GOSUB martial_arts_pose
    DELAY 1000
	GOSUB standard_pose
 GOTO main_exit


'================================================

k50:
	IF RFX_ON = 1 THEN
		GOSUB check_front_obstacle
		IF OBS_HIT = 1 THEN
			GOSUB avoid_obstacle_step
			GOTO main_exit
		ENDIF
	ENDIF
	GOSUB fast_run
	GOSUB standard_pose
	GOTO main_exit
k51:
	GOSUB fast_turn_right
	DELAY 1000
	GOSUB standard_pose
	GOTO main_exit
k52:
	GOSUB fast_turn_left
	DELAY 1000
	GOSUB standard_pose
	GOTO main_exit
k53:
	GOSUB avoid_matrix
	DELAY 1000
	GOSUB standard_pose
	GOTO main_exit
k54:
	GOSUB goalkeeper
	GOSUB standard_pose
	GOTO main_exit
k55:
	GOSUB cheer_up
	GOSUB standard_pose
	GOTO main_exit
k56:
	GOSUB single_foot_standing
	GOSUB standard_pose
	GOTO main_exit
k57:
	GOSUB hand_clapping
	GOSUB standard_pose	
	GOTO main_exit
k58:
	GOSUB hand_shaking
	GOSUB standard_pose
	GOTO main_exit	
k59:
	GOSUB break_dance
	GOSUB standard_pose
	GOTO main_exit	
	
k60:					' ^ 1
	GOSUB sit_forward_walking
	GOSUB standard_pose
	GOTO main_exit	
k61:					' _ 1
	GOSUB sit_backward_walking
	GOSUB standard_pose
	GOTO main_exit
k62:					' > 1
	
	GOSUB sit_left_walking
	GOSUB standard_pose
	GOTO main_exit
k63:					' < 1
	
	GOSUB sit_right_walking
	GOSUB standard_pose
	GOTO main_exit
k64:					' E
	GOSUB dance1
        GOSUB standard_pose	
	GOTO main_exit

k65: GOSUB dance2					' F
	GOSUB standard_pose	
	GOTO main_exit
k66:					' P1
	GOSUB upstair
	GOSUB standard_pose
	GOTO main_exit
k67:
	GOSUB push_up					' [] 1	
	GOSUB standard_pose
	GOTO main_exit

k68:					' G
	GOSUB dance3
	GOSUB standard_pose
	GOTO main_exit	

'================================================
robot_voltage:						' [ 10 x Value / 256 = Voltage]
	DIM v AS BYTE

	A = AD(6)
	
	IF A < 148 THEN 				' 5.8v
	
	FOR v = 0 TO 2
	OUT 52,1
	DELAY 200
	OUT 52,0
	DELAY 200
	NEXT v
	ENDIF	
	RETURN
'================================================
robot_tilt:	
	A = AD(5)
	IF A > 250 THEN RETURN
	  
	IF A < 30 THEN GOTO tilt_low
	IF A > 200 THEN GOTO tilt_high
	
	RETURN
tilt_low:
	A = AD(5)
	'IF A < 30 THEN  GOTO forward_standup
	IF A < 30 THEN  GOTO backward_standup
	RETURN
tilt_high:	
	A = AD(5)
	'IF A > 200 THEN GOTO backward_standup
	IF A > 200 THEN GOTO forward_standup
	RETURN
'================================================
sit_down_pose16:
	IF A16 = 0 THEN GOTO standard_pose16
	A16 = 0
	SPEED 10
	MOVE G6A, 100, 151,  23, 140, 101, 100
	MOVE G6D, 100, 151,  23, 140, 101, 100
	MOVE G6B, 100,  30,  80, 100, 100, 100
	MOVE G6C, 100,  30,  80, 100, 100, 100	
	WAIT
'== motor power off  ============================
	MOTOROFF G24
	TEMPO 230
	MUSIC "FEDC"
	RETURN
'================================================
standard_pose16:
	TEMPO 230
	MUSIC "CDE"
	GETMOTORSET G24,1,1,1,1,1,0,1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,1,1,0
'== motor power on  =============================
	MOTOR G24
	A16 = 1
'================================================
	SPEED 10
	GOSUB standard_pose
	RETURN
'================================================
'================================================
bow_pose:
	MOVE G6A, 100,  58, 135, 160, 100, 100 
	MOVE G6D, 100,  58, 135, 160, 100, 100
	MOVE G6B, 100,  30,  80,  ,  ,  ,
	MOVE G6C, 100,  30,  80,  ,  ,  , 
	WAIT
	DELAY 1000
	RETURN
'================================================
standard_pose:
	MOVE G6A, 100,  76, 145,  93, 100, 100 
	MOVE G6D, 100,  76, 145,  93, 100, 100  
	MOVE G6B, 100,  30,  80, 100, 100, 100
	MOVE G6C, 100,  30,  80, 100, 100, 100
	WAIT
	RETURN
'================================================
'================================================
hans_up:
	SPEED 5
	MOVE G6A, 100,  76, 145,  93, 100
	MOVE G6D, 100,  76, 145,  93, 100	
	MOVE G6B, 100, 168, 150
	MOVE G6C, 100, 168, 150
	WAIT
	RETURN
'================================================
'================================================
sit_down_pose:
	SPEED 10
	MOVE G6A, 100, 151,  23, 140, 101, 100
	MOVE G6D, 100, 151,  23, 140, 101, 100
	MOVE G6B, 100,  30,  80, 100, 100, 100
	MOVE G6C, 100,  30,  80, 100, 100, 100	
	WAIT
	RETURN
'================================================
'================================================
sit_hans_up:
	SPEED 10
	MOVE G6A, 100, 151,  23, 140, 101, 100,
	MOVE G6D, 100, 151,  23, 140, 101, 100
	MOVE G6B, 100, 168, 150
	MOVE G6C, 100, 168, 150
	WAIT
	RETURN
'================================================
'================================================
foot_up:
	SPEED 5
	MOVE G6A,  85,  71, 152,  91, 112,  60,
	MOVE G6D, 112,  76, 145,  93,  92,  60,
	MOVE G6B, 100,  40,  80,    ,    ,    ,
	MOVE G6C, 100,  40,  80,    ,    ,    ,	
	WAIT   
	MOVE G6A,  90,  98, 105, 115, 115,  60,
	MOVE G6D, 116,  74, 145,  98,  93,  60,
	MOVE G6B, 100,  95, 100, 100, 100, 100,
	MOVE G6C, 100, 105, 100, 100, 100, 100,
	WAIT
	MOVE G6A, 100, 151,  23, 140, 115, 100,
	WAIT
	DELAY 1000
	MOVE G6A,  85,  71, 152,  91, 112,  60,
	MOVE G6D, 112,  76, 145,  93,  92,  60,
	WAIT
	RETURN
'================================================
'================================================
body_move:
	SPEED 6
	GOSUB body_move1
	GOSUB body_move2
	GOSUB body_move3
	MOVE G6A,  93,  76, 145,  94, 109, 100
	MOVE G6D,  93,  76, 145,  94, 109, 100
	MOVE G6B, 100,  105, 100, , , ,
	MOVE G6C, 100,  105, 100, , , ,
	WAIT
	MOVE G6A, 104, 112,  92, 116, 107
	MOVE G6D,  79,  81, 145,  95, 108
	MOVE G6B, 100, 105, 100
	MOVE G6C, 100, 105, 100
	WAIT
	MOVE G6A,  93,  76, 145,  94, 109, 100
	MOVE G6D,  93,  76, 145,  94, 109, 100
	MOVE G6B, 100,  105, 100, , , ,
	MOVE G6C, 100,  105, 100, , , ,
	WAIT
	MOVE G6D, 104, 112,  92, 116, 107
	MOVE G6A,  79,  81, 145,  95, 108
	MOVE G6B, 100, 105, 100
	MOVE G6C, 100, 105, 100
	WAIT
	MOVE G6A,  93,  76, 145,  94, 109, 100
	MOVE G6D,  93,  76, 145,  94, 109, 100
	MOVE G6B, 100,  105, 100, , , ,
	MOVE G6C, 100,  105, 100, , , ,
	WAIT
	GOSUB body_move3
	GOSUB body_move2
	GOSUB body_move1
RETURN
'================================================
body_move3:
	MOVE G6A, 93,  76, 145,  94, 109, 100
	MOVE G6D, 93,  76, 145,  94, 109, 100
	MOVE G6B,100,  35,  90, , , ,
	MOVE G6C,100,  35,  90, , , ,
	WAIT
	RETURN
'================================================
body_move2:
	MOVE G6D,110,  92, 124,  97,  93,  70
	MOVE G6A, 76,  72, 160,  82, 128,  70
	MOVE G6B,100,  35,  90, , , ,
	MOVE G6C,100,  35,  90, , , ,
	WAIT
	RETURN
'================================================
body_move1:
	MOVE G6A, 85,  71, 152,  91, 112, 60
	MOVE G6D,112,  76, 145,  93,  92, 60
	MOVE G6B,100,  40,  80, , , ,
	MOVE G6C,100,  40,  80, , , ,	
	WAIT
	RETURN
'================================================
'================================================
wing_move:
	DIM i AS BYTE
	SPEED 5
	
	MOVE G6A, 85,  71, 152,  91, 112,  60
	MOVE G6D,112,  76, 145,  93,  92,  60
	MOVE G6B,100,  40,  80, , , ,
	MOVE G6C,100,  40,  80, , , ,	
	WAIT
	
	MOVE G6A, 90,  98, 105, 115, 115,  60
	MOVE G6D,116,  74, 145,  98,  93,  60
	MOVE G6B,100, 150, 150, 100, 100, 100
	MOVE G6C,100, 150, 150, 100, 100, 100
	WAIT
	
	MOVE G6A, 90, 121,  36, 105, 115,  60
	MOVE G6D,116,  60, 146, 138,  93,  60
	MOVE G6B,100, 150, 150, 100, 100, 100
	MOVE G6C,100, 150, 150, 100, 100, 100
	WAIT

	MOVE G6A, 90,  98, 105,  64, 115,  60
	MOVE G6D,116,  50, 160, 160,  93,  60
	MOVE G6B,145, 110, 110, 100, 100, 100
	MOVE G6C,145, 110, 110, 100, 100, 100
	WAIT

	FOR i = 10 TO 15
		SPEED i
		MOVE G6B,145,  80,  80, 100, 100, 100
		MOVE G6C,145,  80,  80, 100, 100, 100
		WAIT
	
		MOVE G6B,145, 120, 120, 100, 100, 100
		MOVE G6C,145, 120, 120, 100, 100, 100
		WAIT
	NEXT i

	DELAY 1000
	SPEED 6

	MOVE G6A, 90,  98, 105,  64, 115,  60
	MOVE G6D,116,  50, 160, 160,  93,  60
	MOVE G6B,100, 160, 180, 100, 100, 100
	MOVE G6C,100, 160, 180, 100, 100, 100
	WAIT

	MOVE G6A, 90, 121,  36, 105, 115,  60
	MOVE G6D,116,  60, 146, 138,  93,  60
	MOVE G6B,100, 150, 150, 100, 100, 100
	MOVE G6C,100, 150, 150, 100, 100, 100
	WAIT
	SPEED 4

	MOVE G6A, 90,  98, 105, 115, 115,  60
	MOVE G6D,116,  74, 145,  98,  93,  60
	WAIT
	
	MOVE G6A, 85,  71, 152,  91, 112,  60
	MOVE G6D,112,  76, 145,  93,  92,  60
	MOVE G6B,100,  40,  80, , , ,
	MOVE G6C,100,  40,  80, , , ,	
	WAIT
	RETURN
'================================================
'================================================
right_shoot:
	SPEED 4
MOVE G6A,112,  56, 180,  79, 104, 100
MOVE G6D, 70,  56, 180,  79, 102, 100
MOVE G6B,110,  45,  70, 100, 100, 100
MOVE G6C, 90,  45,  70, 100, 100, 100
WAIT
right_shoot1:
	SPEED 6
MOVE G6A,115,  60, 180,  79,  95, 100
MOVE G6D, 90,  90, 127,  65, 116, 100
MOVE G6B, 80,  45,  70, 100, 100, 100
MOVE G6C,120,  45,  70, 100, 100, 100
WAIT
	SPEED 15
	HIGHSPEED SETON
right_shoot2:
MOVE G6A,115,  52, 180,  79,  95, 100
MOVE G6D, 90,  90, 127, 147, 116, 100
MOVE G6B,140,  45,  70, 100, 100, 100
MOVE G6C, 60,  45,  70, 100, 100, 100
WAIT
	DELAY 500
	HIGHSPEED SETOFF
right_shoot3:
	SPEED 5
MOVE G6A,115,  76, 145,  93, 102, 100
MOVE G6D, 70,  76, 145,  93, 104, 100
MOVE G6B,110,  45,  70, 100, 100, 100
MOVE G6C, 90,  45,  70, 100, 100, 100
WAIT
RETURN	
'================================================
left_shoot:
	SPEED 4
MOVE G6A, 70,  56, 180,  79, 102, 100
MOVE G6D,112,  56, 180,  79, 104, 100
MOVE G6B, 90,  45,  70, 100, 100, 100
MOVE G6C,110,  45,  70, 100, 100, 100
WAIT
left_shoot1:
	SPEED 6
MOVE G6A, 90,  90, 127,  65, 116, 100
MOVE G6D,115,  60, 180,  79,  95, 100
MOVE G6B,140,  45,  70, 100, 100, 100
MOVE G6C, 60,  45,  70, 100, 100, 100
WAIT
	SPEED 15
	HIGHSPEED SETON
left_shoot2:
MOVE G6A, 90,  90, 127, 147, 116, 100
MOVE G6D,115,  52, 180,  79,  95, 100
MOVE G6B, 60,  45,  70, 100, 100, 100
MOVE G6C,140,  45,  70, 100, 100, 100
WAIT
	DELAY 500
	HIGHSPEED SETOFF
left_shoot3:
	SPEED 5
MOVE G6A, 70,  76, 145,  93, 104, 100
MOVE G6D,115,  76, 145,  93, 102, 100
MOVE G6B, 90,  45,  70, 100, 100, 100
MOVE G6C,110,  45,  70, 100, 100, 100
WAIT
RETURN
'================================================
'================================================
handstanding:
	GOSUB fall_forward
	GOSUB standard_pose
	GOSUB foot_up2
 	GOSUB standard_pose
	GOSUB back_stand_up
RETURN
'================================================
fall_forward:
	SPEED 10
	MOVE G6A, 100, 155,  25, 140, 100, 100
	MOVE G6D, 100, 155,  25, 140, 100, 100
	MOVE G6B, 130,  50,  85, 100, 100, 100
	MOVE G6C, 130,  50,  85, 100, 100, 100
	WAIT
	MOVE G6A,  60, 165,  25, 160, 145, 100
	MOVE G6D,  60, 165,  25, 160, 145, 100
	MOVE G6B, 150,  60,  90, 100, 100, 100
	MOVE G6C, 150,  60,  90, 100, 100, 100
	WAIT
	MOVE G6A,  60, 165,  30, 165, 155, 100
	MOVE G6D,  60, 165,  30, 165, 155, 100
	MOVE G6B, 170,  10, 100, 100, 100, 100
	MOVE G6C, 170,  10, 100, 100, 100, 100
	WAIT
	SPEED 3
	MOVE G6A,  75, 165,  55, 165, 155, 100
	MOVE G6D,  75, 165,  55, 165, 155, 100
	MOVE G6B, 185,  10, 100, 100, 100, 100
	MOVE G6C, 185,  10, 100, 100, 100, 100
	WAIT
	SPEED 10
	MOVE G6A,  80, 155,  85, 150, 150, 100
	MOVE G6D,  80, 155,  85, 150, 150, 100
	MOVE G6B, 185,  40, 60,  100, 100, 100
	MOVE G6C, 185,  40, 60,  100, 100, 100
	WAIT
	MOVE G6A, 100, 130, 120,  80, 110, 100
	MOVE G6D, 100, 130, 120,  80, 110, 100
	MOVE G6B, 125, 160,  10, 100, 100, 100
	MOVE G6C, 125, 160,  10, 100, 100, 100
	WAIT	
	RETURN
'================================================
foot_up2:
	SPEED 6
	MOVE G6A, 100, 125,  65,  10, 100,    ,  
	MOVE G6D, 100, 125,  65,  10, 100,    , 
	MOVE G6B, 110,  30,  80,    ,    ,    , 
	MOVE G6C, 110,  30,  80,    ,    ,    , 
	SPEED 3
	MOVE G6A, 100, 125,  65,  10, 100,    ,
	MOVE G6D, 100, 125,  65,  10, 100,    ,
	MOVE G6B, 170,  30,  80,    ,    ,    ,
	MOVE G6C, 170,  30,  80,    ,    ,    , 
	WAIT
	DELAY 200
	SPEED 6
	MOVE G6A, 100,  89, 129,  57, 100,    , 
	MOVE G6D, 100,  89, 129,  57, 100,    , 
	MOVE G6B, 180,  30,  80,    ,    ,    ,
	MOVE G6C, 180,  30,  80,    ,    ,    , 
	WAIT
	MOVE G6A, 100,  64, 179,  57, 100,    ,   
	MOVE G6D, 100,  64, 179,  57, 100,    ,  
	MOVE G6B, 190,  50,  80,    ,    ,    ,
	MOVE G6C, 190,  50,  80,    ,    ,    ,
	WAIT
	DELAY 2000
	MOVE G6A, 100,  64, 179,  57, 100,    ,   
	MOVE G6D, 100,  64, 179,  57, 100,    ,   
	MOVE G6B, 190,  50,  80,    ,    ,    ,
	MOVE G6C, 190,  50,  80,    ,    ,    ,
	WAIT
	MOVE G6A, 100,  89, 129,  57, 100,    , 
	MOVE G6D, 100,  89, 129,  57, 100,    ,   
	MOVE G6B, 180,  30,  80,    ,    ,    ,
	MOVE G6C, 180,  30,  80,    ,    ,    ,
	WAIT
	SPEED 3
	MOVE G6A, 100, 125,  65,  10, 100,    , 
	MOVE G6D, 100, 125,  65,  10, 100,    ,   
	MOVE G6B, 170,  30,  80,    ,    ,    ,
	MOVE G6C, 170,  30,  80,    ,    ,    ,
	WAIT
	SPEED 6
	MOVE G6A, 100, 125,  65,  10, 100,    ,   
	MOVE G6D, 100, 125,  65,  10, 100,    ,  
	MOVE G6B, 110,  30,  80,    ,    ,    ,
	MOVE G6C, 110,  30,  80,    ,    ,    ,
	WAIT
	RETURN
'================================================	
back_stand_up:
	SPEED 10
	MOVE G6A, 100, 130, 120,  80, 110, 100
	MOVE G6D, 100, 130, 120,  80, 110, 100
	MOVE G6B, 150, 160,  10, 100, 100, 100
	MOVE G6C, 150, 160,  10, 100, 100, 100
	WAIT
	MOVE G6A,  80, 155,  85, 150, 150, 100
	MOVE G6D,  80, 155,  85, 150, 150, 100
	MOVE G6B, 185,  40, 60,  100, 100, 100
	MOVE G6C, 185,  40, 60,  100, 100, 100
	WAIT
	MOVE G6A,  75, 165,  55, 165, 155, 100
	MOVE G6D,  75, 165,  55, 165, 155, 100
	MOVE G6B, 185,  10, 100, 100, 100, 100
	MOVE G6C, 185,  10, 100, 100, 100, 100
	WAIT	
	MOVE G6A,  60, 165,  30, 165, 155, 100
	MOVE G6D,  60, 165,  30, 165, 155, 100
	MOVE G6B, 170,  10, 100, 100, 100, 100
	MOVE G6C, 170,  10, 100, 100, 100, 100
	WAIT	
	MOVE G6A,  60, 165,  25, 160, 145, 100
	MOVE G6D,  60, 165,  25, 160, 145, 100
	MOVE G6B, 150,  60,  90, 100, 100, 100
	MOVE G6C, 150,  60,  90, 100, 100, 100
	WAIT	
	MOVE G6A, 100, 155,  25, 140, 100, 100
	MOVE G6D, 100, 155,  25, 140, 100, 100
	MOVE G6B, 130,  50,  85, 100, 100, 100
	MOVE G6C, 130,  50,  85, 100, 100, 100
	WAIT	
	RETURN
'================================================	
'================================================
fast_walk: 
DIM A10 AS BYTE
	SPEED 10
	MOVE G6B,100,  30,  90, 100, 100, 100
	MOVE G6C,100,  30,  90, 100, 100, 100
	WAIT
	SPEED 7
fast_run01:
	MOVE G6A, 90,  72, 148,  93, 110,  70
	MOVE G6D,108,  75, 145,  93,  95,  70
	WAIT
	SPEED 15
fast_run02:
	MOVE G6A, 90,  95, 105, 115, 110,  70
	MOVE G6D,112,  75, 145,  93,  95,  70
	MOVE G6B, 90,  30,  90, 100, 100, 100
	MOVE G6C,110,  30,  90, 100, 100, 100
	WAIT
	SPEED 15
'----------------------------  4 times
	FOR A10 = 1 TO 4

fast_run20:
	MOVE G6A,100,  80, 119, 118, 106, 100
	MOVE G6D,105,  75, 145,  93, 100, 100
	MOVE G6B, 80,  30,  90, 100, 100, 100
	MOVE G6C,120,  30,  90, 100, 100, 100
fast_run21:
	MOVE G6A,105,  74, 140, 106, 100, 100
	MOVE G6D, 95, 105, 124,  93, 106, 100
	MOVE G6B,100,  30,  90, 100, 100, 100
	MOVE G6C,100,  30,  90, 100, 100, 100
fast_run22:
	MOVE G6D,100,  80, 119, 118, 106, 100
	MOVE G6A,105,  75, 145,  93, 100, 100
	MOVE G6C, 80,  30,  90, 100, 100, 100
	MOVE G6B,120,  30,  90, 100, 100, 100
fast_run23:
	MOVE G6D,105,  74, 140, 106, 100, 100
	MOVE G6A, 95, 105, 124,  93, 106, 100
	MOVE G6C,100,  30,  90, 100, 100, 100
	MOVE G6B,100,  30,  90, 100, 100, 100

	NEXT A10
'------------------------------
	SPEED 8
	MOVE G6A, 85,  80, 130,  95, 106, 100
	MOVE G6D,108,  73, 145,  93, 100, 100
	MOVE G6B, 80,  30,  90, 100, 100, 100
	MOVE G6C,120,  30,  90, 100, 100, 100
	WAIT
fast_run03:
	MOVE G6A, 90,  72, 148,  93, 110,  70
	MOVE G6D,108,  75, 145,  93,  93,  70
	WAIT
	SPEED 5

	RETURN
'================================================
'================================================
left_turn:
	SPEED 6
	MOVE G6D,  85,  71, 152,  91, 112,  60  
	MOVE G6A, 112,  76, 145,  93,  92,  60 
	MOVE G6C, 100,  40,  80,    ,    ,    ,
	MOVE G6B, 100,  40,  80,    ,    ,    ,
	WAIT

	SPEED 9
	MOVE G6A, 113,  75, 145,  97,  93,  60
	MOVE G6D,  90,  50, 157, 115, 112,  60 
	MOVE G6B, 105,  40,  70,    ,    ,    , 
	MOVE G6C,  90,  40,  70,    ,    ,    , 
	WAIT   

	MOVE G6A, 108,  78, 145,  98,  93,  60
	MOVE G6D,  95,  43, 169, 110, 110,  60 
	MOVE G6B, 105,  40,  70,    ,    ,    ,
	MOVE G6C,  80,  40,  70,    ,    ,    , 
	WAIT
	RETURN
'================================================
'================================================
right_turn:
	SPEED 6
	MOVE G6A,  85,  71, 152,  91, 112,  60  
	MOVE G6D, 112,  76, 145,  93,  92,  60 
	MOVE G6B, 100,  40,  80,    ,    ,    ,
	MOVE G6C, 100,  40,  80,    ,    ,    ,
	WAIT

	SPEED 9
	MOVE G6D, 113,  75, 145,  97,  93,  60
	MOVE G6A,  90,  50, 157, 115, 112,  60 
	MOVE G6C, 105,  40,  70,    ,    ,    , 
	MOVE G6B,  90,  40,  70,    ,    ,    , 
	WAIT   

	MOVE G6D, 108,  78, 145,  98,  93,  60
	MOVE G6A,  95,  43, 169, 110, 110,  60 
	MOVE G6C, 105,  40,  70,    ,    ,    ,
	MOVE G6B,  80,  40,  70,    ,    ,    , 
	WAIT
	RETURN
'================================================
'================================================
forward_walk:

	SPEED 5
MOVE24  85,  71, 152,  91, 112,  60, 100,  40,  80,    ,    ,    , 100,  40,  80,    ,    ,    , 112,  76, 145,  93,  92,  60,
	
	SPEED 14 
'left up
MOVE24  90, 107, 105, 105, 114,  60,  90,  40,  80,    ,    ,    , 100,  40,  80,    ,    ,    , 114,  76, 145,  93,  90,  60,
'---------------------------------------
'left down
MOVE24  90,  56, 143, 122, 114,  60,  80,  40,  80,    ,    ,    , 105,  40,  80,    ,    ,    , 113,  80, 145,  90,  90,  60,
MOVE24  90,  46, 163, 112, 114,  60,  80,  40,  80,    ,    ,    , 105,  40,  80,    ,    ,    , 112,  80, 145,  90,  90,  60,
	
	SPEED 10
'left center
MOVE24 100,  66, 141, 113, 100, 100,  90,  40,  80,    ,    ,    , 100,  40,  80,    ,    ,    , 100,  83, 156,  80, 100, 100,
MOVE24 113,  78, 142, 105,  90,  60, 100,  40,  80,    ,    ,    , 100,  40,  80,    ,    ,    ,  90, 102, 136,  85, 114,  60,

	SPEED 14
'right up
MOVE24 113,  76, 145,  93,  90,  60, 100,  40,  80,    ,    ,    ,  90,  40,  80,    ,    ,    ,  90, 107, 105, 105, 114,  60,
			
'right down
MOVE24 113,  80, 145,  90,  90,  60, 105,  40,  80,    ,    ,    ,  80,  40,  80,    ,    ,    ,  90,  56, 143, 122, 114,  60,
MOVE24 112,  80, 145,  90,  90,  60, 105,  40,  80,    ,    ,    ,  80,  40,  80,    ,    ,    ,  90,  46, 163, 112, 114,  60,
		
	SPEED 10
'right center
MOVE24 100,  83, 156,  80, 100, 100, 100,  40,  80,    ,    ,    ,  90,  40,  80,    ,    ,    , 100,  66, 141, 113, 100, 100,
MOVE24  90, 102, 136,  85, 114,  60, 100,  40,  80,    ,    ,    , 100,  40,  80,    ,    ,    , 113,  78, 142, 105,  90,  60,
		
	SPEED 14
'left up
MOVE24  90, 107, 105, 105, 114,  60,  90,  40,  80,    ,    ,    , 100,  40,  80,    ,    ,    , 113,  76, 145,  93,  90,  60,
'---------------------------------------

	SPEED 5
MOVE24  85,  71, 152,  91, 112,  60, 100,  40,  80,    ,    ,    , 100,  40,  80,    ,    ,    , 112,  76, 145,  93,  92,  60,
	
	RETURN
'================================================
'================================================
left_shift:

	SPEED 5
	GOSUB left_shift1
	SPEED 9
	GOSUB left_shift2
	
	GOSUB left_shift3
	GOSUB left_shift4
	
	SPEED 9
	GOSUB left_shift5
	GOSUB left_shift6
	
	RETURN
'================================================
left_shift1:
	MOVE G6A,  85,  71, 152,  91, 112,  60,
	MOVE G6D, 112,  76, 145,  93,  92,  60,
	MOVE G6B, 100,  40,  80,    ,    ,    ,
	MOVE G6C, 100,  40,  80,    ,    ,    ,	
	WAIT
	RETURN
'---------------------------
left_shift2:
	MOVE G6D, 110,  92, 124,  97,  93,  70,
	MOVE G6A,  76,  72, 160,  82, 128,  70,
	MOVE G6B, 100,  35,  90,    ,    ,    ,
	MOVE G6C, 100,  35,  90,    ,    ,    ,
	WAIT
	RETURN
'---------------------------
left_shift3:
	MOVE G6A,  93,  76, 145,  94, 109, 100,
	MOVE G6D,  93,  76, 145,  94, 109, 100,
	MOVE G6B, 100,  35,  90,    ,    ,    ,
	MOVE G6C, 100,  35,  90,    ,    ,    ,
	WAIT
	RETURN
'---------------------------
left_shift4:
	MOVE G6A, 110,  92, 124,  97,  93,  70,
	MOVE G6D,  76,  72, 160,  82, 128,  70,
	MOVE G6B, 100,  35,  90,    ,    ,    ,
	MOVE G6C, 100,  35,  90,    ,    ,    ,
	WAIT
	RETURN
'---------------------------
left_shift5:
	MOVE G6D,  86,  83, 135,  97, 114,  60,
	MOVE G6A, 113,  78, 145,  93,  93,  60,
	MOVE G6C,  90,  40,  80,    ,    ,    , 
	MOVE G6B, 100,  40,  80,    ,    ,    , 
	WAIT
	RETURN
'---------------------------	
left_shift6:
	MOVE G6D,  85,  71, 152,  91, 112,  60,
	MOVE G6A, 112,  76, 145,  93,  92,  60,
	MOVE G6C, 100,  40,  80,    ,    ,    ,
	MOVE G6B, 100,  40,  80,    ,    ,    ,
	WAIT
	RETURN
'================================================
'================================================
sit_down_pose26:
	IF A26 = 0 THEN GOTO standard_pose26

	A26 = 0
	SPEED 10
	MOVE G6A,100, 151,  23, 140, 101, 100
	MOVE G6D,100, 151,  23, 140, 101, 100
	MOVE G6B,100,  30,  80, 100, 100, 100
	MOVE G6C,100,  30,  80, 100, 100, 100	
	WAIT

	RETURN
'================================================
standard_pose26:
	A26 = 1
	MOVE G6A,100,  76, 145,  93, 100, 100 
	MOVE G6D,100,  76, 145,  93, 100, 100  
	MOVE G6B,100,  30,  80, 100, 100, 100
	MOVE G6C,100,  30,  80, 100, 100, 100
	WAIT
	
	RETURN
'================================================
'================================================
right_shift:

	SPEED 5
	GOSUB right_shift1
	
	SPEED 9
	GOSUB right_shift2
	
	GOSUB right_shift3
	
	GOSUB right_shift4
	
	SPEED 9
	GOSUB right_shift5
	GOSUB right_shift6
	
	RETURN
'================================================
right_shift1:
	MOVE G6D,  85,  71, 152,  91, 112, 60  
	MOVE G6A, 112,  76, 145,  93,  92, 60 
	MOVE G6C, 100,  40,  80,  ,  ,  ,
	MOVE G6B, 100,  40,  80,  ,  ,  ,
	WAIT
	RETURN
	
right_shift2:
	MOVE G6A,110,  92, 124,  97,  93,  70
	MOVE G6D, 76,  72, 160,  82, 128,  70
	MOVE G6B,100,  35,  90, , , ,
	MOVE G6C,100,  35,  90, , , ,
	WAIT
	RETURN

right_shift3:
	MOVE G6A, 93,  76, 145,  94, 109, 100
	MOVE G6D, 93,  76, 145,  94, 109, 100
	MOVE G6B,100,  35,  90, , , ,
	MOVE G6C,100,  35,  90, , , ,
	WAIT
	RETURN

right_shift4:
	MOVE G6D,110,  92, 124,  97,  93,  70
	MOVE G6A, 76,  72, 160,  82, 128,  70
	MOVE G6B,100,  35,  90, , , ,
	MOVE G6C,100,  35,  90, , , ,
	WAIT
	RETURN

right_shift5:
	MOVE G6A, 86,  83, 135,  97, 114,  60
	MOVE G6D,113,  78, 145,  93,  93,  60
	MOVE G6B, 90,  40,  80, , , ,
	MOVE G6C,100,  40,  80, , , ,
	WAIT
	RETURN

right_shift6:
	MOVE G6A, 85,  71, 152,  91, 112,  60
	MOVE G6D,112,  76, 145,  93,  92,  60
	MOVE G6B,100,  40,  80, , , ,
	MOVE G6C,100,  40,  80, , , ,	
	WAIT
	RETURN
'================================================	
'================================================
backward_walk:

	SPEED 5
	GOSUB backward_walk1
	
	SPEED 13
	GOSUB backward_walk2
	
	SPEED 7
	GOSUB backward_walk3
	GOSUB backward_walk4
	GOSUB backward_walk5

	SPEED 13
	GOSUB backward_walk6
		
	SPEED 7
	GOSUB backward_walk7
	GOSUB backward_walk8
	GOSUB backward_walk9

	SPEED 13
	GOSUB backward_walk2

	SPEED 5
	GOSUB backward_walk1

	RETURN
'================================================
backward_walk1:
	MOVE G6A, 85,  71, 152,  91, 112,  60
	MOVE G6D,112,  76, 145,  93,  92,  60
	MOVE G6B,100,  40,  80, , , ,
	MOVE G6C,100,  40,  80, , , ,	
	WAIT
	RETURN

backward_walk2:
	MOVE G6A, 90, 107, 105, 105, 114,  60
	MOVE G6D,113,  78, 145,  93,  90,  60
	MOVE G6B, 90,  40,  80, , , ,
	MOVE G6C,100,  40,  80, , , ,
	WAIT
	RETURN
	
backward_walk9:
	MOVE G6A, 90,  56, 143, 122, 114,  60
	MOVE G6D,113,  80, 145,  90,  90,  60
	MOVE G6B, 80,  40,  80, , , ,
	MOVE G6C,105,  40,  80, , , ,
	WAIT
	RETURN

backward_walk8:
	MOVE G6A,100,  62, 146, 108, 100, 100
	MOVE G6D,100,  88, 140,  86, 100, 100
	MOVE G6B, 90,  40,  80, , , ,
	MOVE G6C,100,  40,  80, , , ,
	WAIT
	RETURN
		
backward_walk7:
	MOVE G6A,113,  76, 142, 105,  90,  60
	MOVE G6D, 90,  96, 136,  85, 114,  60	
	MOVE G6B,100,  40,  80, , , ,
	MOVE G6C,100,  40,  80, , , , 
	WAIT
	RETURN

backward_walk6:
	MOVE G6D, 90, 107, 105, 105, 114,  60
	MOVE G6A,113,  78, 145,  93,  90,  60
	MOVE G6C,90,  40,  80, , , , 
	MOVE G6B,100,  40,  80, , , , 
	WAIT
	RETURN

backward_walk5:
	MOVE G6D, 90,  56, 143, 122, 114,  60
	MOVE G6A,113,  80, 145,  90,  90,  60
	MOVE G6C,80,  40,  80, , , , 
	MOVE G6B,105,  40,  80, , , , 
	WAIT
	RETURN

backward_walk4:
	MOVE G6D,100,  62, 146, 108, 100, 100 
	MOVE G6A,100,  88, 140,  86, 100, 100
	MOVE G6C,90,  40,  80, , ,,
	MOVE G6B,100,  40,  80, , , , 
	WAIT
	RETURN

backward_walk3:
	MOVE G6D,113,  76, 142, 105,  90,  60
	MOVE G6A, 90,  96, 136,  85, 114,  60
	MOVE G6C,100,  40,  80, , , ,
	MOVE G6B,100,  40,  80, , , ,
	WAIT
	RETURN
'================================================
'================================================
forward_tumbling:

SPEED 8
GOSUB standard_pose
MOVE G6A,100, 155,  20, 140, 100, 100
MOVE G6D,100, 155,  20, 140, 100, 100
MOVE G6B,130,  50,  85, 100, 100, 100
MOVE G6C,130,  50,  85, 100, 100, 100
WAIT

MOVE G6A, 60, 165,  30, 165, 155, 100
MOVE G6D, 60, 165,  30, 165, 155, 100
MOVE G6B,170,  10, 100, 100, 100, 100
MOVE G6C,170,  10, 100, 100, 100, 100
WAIT

MOVE G6A, 75, 165,  55, 165, 155, 100
MOVE G6D, 75, 165,  55, 165, 155, 100
MOVE G6B,185,  10, 100, 100, 100, 100
MOVE G6C,185,  10, 100, 100, 100, 100
WAIT

MOVE G6A, 80, 155,  85, 150, 150, 100
MOVE G6D, 80, 155,  85, 150, 150, 100
MOVE G6B,185,  40, 60,  100, 100, 100
MOVE G6C,185,  40, 60,  100, 100, 100
WAIT

MOVE G6A,100, 130, 120,  80, 110, 100
MOVE G6D,100, 130, 120,  80, 110, 100
MOVE G6B,130, 160,  10, 100, 100, 100
MOVE G6C,130, 160,  10, 100, 100, 100
WAIT

MOVE G6A,100, 160, 110, 140, 100, 100
MOVE G6D,100, 160, 110, 140, 100, 100
MOVE G6B,140,  70,  20, 100, 100, 100
MOVE G6C,140,  70,  20, 100, 100, 100
WAIT

SPEED 15
MOVE G6A,100,  56, 110,  26, 100, 100
MOVE G6D,100,  71, 177, 162, 100, 100
MOVE G6B,170,  40,  50, 100, 100, 100
MOVE G6C,170,  40,  50, 100, 100, 100
WAIT

MOVE G6A,100,  62, 110,  15, 100, 100
MOVE G6D,100,  71, 128, 113, 100, 100
MOVE G6B,190,  40,  50, 100, 100, 100
MOVE G6C,190,  40,  50, 100, 100, 100
WAIT

SPEED 15
MOVE G6A,100,  55, 110,  15, 100, 100
MOVE G6D,100,  55, 110,  15, 100, 100
MOVE G6B,190,  40,  50, 100, 100, 100
MOVE G6C,190,  40,  50, 100, 100, 100
WAIT

SPEED 10

MOVE G6A,100, 110, 100,  15, 100, 100
MOVE G6D,100, 110, 100,  15, 100, 100
MOVE G6B,170, 160, 115, 100, 100, 100
MOVE G6C,170, 160, 115, 100, 100, 100
WAIT

MOVE G6A,100, 170,  70,  15, 100, 100
MOVE G6D,100, 170,  70,  15, 100, 100
MOVE G6B,190, 170, 120, 100, 100, 100
MOVE G6C,190, 170, 120, 100, 100, 100
WAIT

MOVE G6A,100, 170,  30, 110, 100, 100
MOVE G6D,100, 170,  30, 110, 100, 100
MOVE G6B,190,  40,  60, 100, 100, 100
MOVE G6C,190,  40,  60, 100, 100, 100
WAIT

GOSUB sit_pose
GOSUB standard_pose
RETURN
'================================================
sit_pose:

	SPEED 10
	MOVE G6A,100, 151,  23, 140, 101, 100,
	MOVE G6D,100, 151,  23, 140, 101, 100,
	MOVE G6B,100,  30,  80, 100, 100, 100,
	MOVE G6C,100,  30,  80, 100, 100, 100,	
	WAIT
	RETURN
'================================================
'================================================
left_tumbling:

SPEED 8
MOVE G6A,100, 135,  60, 123, 100, 100
MOVE G6D,100, 135,  60, 123, 100, 100
MOVE G6B,100, 120, 140, 100, 100, 100
MOVE G6C,100, 120, 140, 100, 100, 100
WAIT


DELAY 100
SPEED 3
MOVE G6A,114, 135,  60, 123, 105, 100
MOVE G6D, 88, 110,  91, 116, 100, 100
MOVE G6B,100, 120, 140, 100, 100, 100
MOVE G6C,100, 120, 140, 100, 100, 100
WAIT
DELAY 100
MOVE G6A,114, 135,  60, 123, 105, 100
MOVE G6D,89,  135,  60, 123, 100, 100
MOVE G6B,100, 120, 140, 100, 100, 100
MOVE G6C,100, 120, 140, 100, 100, 100
WAIT

MOVE G6A,120, 135,  60, 123, 110, 100
MOVE G6D, 89, 135,  60, 123, 130, 100
MOVE G6B,100, 120, 140, 100, 100, 100
MOVE G6C,100, 120, 140, 100, 100, 100
WAIT

SPEED 4
MOVE G6A,120, 135,  60, 123, 120, 100
MOVE G6D,89,  135,  60, 123, 158, 100
MOVE G6B,100, 165, 185, 100, 100, 100
MOVE G6C,100, 165, 185, 100, 100, 100
WAIT

SPEED 8
MOVE G6A,120, 131,  60, 123, 185, 100
MOVE G6D,120, 131,  60, 123, 183, 100
MOVE G6B,100, 165, 185, 100, 100, 100
MOVE G6C,100, 165, 185, 100, 100, 100
WAIT

DELAY 200

SPEED 5
MOVE G6A,120, 131,  60, 123, 185, 100
MOVE G6D,120, 131,  60, 123, 183, 100
MOVE G6B,100, 120, 145, 100, 100, 100
MOVE G6C,100, 120, 145, 100, 100, 100
WAIT

SPEED 6

MOVE G6A, 86, 112,  73, 127, 101, 100
MOVE G6D,105, 131,  60, 123, 183, 100
MOVE G6B,100, 120, 145, 100, 100, 100
MOVE G6C,100, 120, 145, 100, 100, 100
WAIT

SPEED 3
MOVE G6A, 86, 118,  73, 127, 101, 100
MOVE G6D,112, 131,  62, 123, 133, 100
MOVE G6B,100,  80,  80, 100, 100, 100
MOVE G6C,100,  80,  80, 100, 100, 100
WAIT

SPEED 3
MOVE G6A, 88, 115,  86, 115,  90, 100
MOVE G6D,107, 135,  62, 123, 113, 100
MOVE G6B,100,  80,  80, 100, 100, 100
MOVE G6C,100,  80,  80, 100, 100, 100
WAIT

SPEED 4
MOVE G6A,100, 135,  60, 123, 100, 100
MOVE G6D,100, 135,  60, 123, 100, 100
MOVE G6B,100,  80,  80, 100, 100, 100
MOVE G6C,100,  80,  80, 100, 100, 100
WAIT

RETURN
'================================================
'================================================
forward_punch:
	SPEED 15
	MOVE G6A, 92, 100, 110, 100, 107, 100
	MOVE G6D, 92, 100, 110, 100, 107, 100
	MOVE G6B,190, 150,  10, 100, 100, 100
	MOVE G6C,190, 150,  10, 100, 100, 100
	WAIT
	SPEED 15
	HIGHSPEED SETON

	MOVE G6B,190,  10,  75, 100, 100, 100
	MOVE G6C,190, 140,  10, 100, 100, 100
	WAIT
	DELAY 500
	MOVE G6B,190, 140,  10, 100, 100, 100
	MOVE G6C,190,  10,  75, 100, 100, 100
	WAIT
	DELAY 500
	
	MOVE G6A, 92, 100, 113, 100, 107, 100
	MOVE G6D, 92, 100, 113, 100, 107, 100
	MOVE G6B,190, 150,  10, 100, 100, 100
	MOVE G6C,190, 150,  10, 100, 100, 100
	WAIT
	
	HIGHSPEED SETOFF
	MOVE G6A,100, 115,  90, 110, 100, 100
	MOVE G6D,100, 115,  90, 110, 100, 100
	MOVE G6B,100,  80,  60, 100, 100, 100
	MOVE G6C,100,  80,  60, 100, 100, 100
	WAIT
	RETURN
'================================================
'================================================
righ_tumbling:

SPEED 8
MOVE G6A,100, 135,  60, 123, 100, 100
MOVE G6D,100, 135,  60, 123, 100, 100
MOVE G6B,100, 120, 140, 100, 100, 100
MOVE G6C,100, 120, 140, 100, 100, 100
WAIT
DELAY 100

SPEED 3
MOVE G6A, 83, 110,  91, 116, 100, 100
MOVE G6D,114, 135,  60, 123, 105, 100
MOVE G6B,100, 120, 140, 100, 100, 100
MOVE G6C,100, 120, 140, 100, 100, 100
WAIT
DELAY 100

MOVE G6A,89,  135,  60, 123, 100, 100
MOVE G6D,114, 135,  60, 123, 105, 100
MOVE G6B,100, 120, 140, 100, 100, 100
MOVE G6C,100, 120, 140, 100, 100, 100
WAIT

MOVE G6A, 89, 135,  60, 123, 130, 100
MOVE G6D,120, 135,  60, 123, 110, 100
MOVE G6B,100, 120, 140, 100, 100, 100
MOVE G6C,100, 120, 140, 100, 100, 100
WAIT

SPEED 4
MOVE G6A,89,  135,  60, 123, 158, 100
MOVE G6D,120, 135,  60, 123, 120, 100
MOVE G6B,100, 165, 185, 100, 100, 100
MOVE G6C,100, 165, 185, 100, 100, 100
WAIT

SPEED 8
MOVE G6A,120, 131,  60, 123, 183, 100
MOVE G6D,120, 131,  60, 123, 185, 100
MOVE G6B,100, 165, 185, 100, 100, 100
MOVE G6C,100, 165, 185, 100, 100, 100
WAIT

DELAY 200

SPEED 5
MOVE G6A,120, 131,  60, 123, 183, 100
MOVE G6D,120, 131,  60, 123, 185, 100
MOVE G6B,100, 120, 145, 100, 100, 100
MOVE G6C,100, 120, 145, 100, 100, 100
WAIT

SPEED 6
MOVE G6A,105, 131,  60, 123, 183, 100
MOVE G6D, 86, 112,  73, 127, 101, 100
MOVE G6B,100, 120, 145, 100, 100, 100
MOVE G6C,100, 120, 145, 100, 100, 100
WAIT

SPEED 3
MOVE G6A,112, 131,  62, 123, 133, 100
MOVE G6D, 86, 118,  73, 127, 101, 100
MOVE G6B,100,  80,  80, 100, 100, 100
MOVE G6C,100,  80,  80, 100, 100, 100
WAIT

SPEED 3
MOVE G6A,107, 135,  62, 123, 113, 100
MOVE G6D, 88, 115,  89, 115,  90, 100
MOVE G6B,100,  80,  80, 100, 100, 100
MOVE G6C,100,  80,  80, 100, 100, 100
WAIT

SPEED 4
MOVE G6A,100, 135,  60, 123, 100, 100
MOVE G6D,100, 135,  60, 123, 100, 100
MOVE G6B,100,  80,  80, 100, 100, 100
MOVE G6C,100,  80,  80, 100, 100, 100
WAIT

RETURN
'================================================
'================================================
back_tumbling:

SPEED 8
GOSUB standard_pose
MOVE G6A, 100, 170,  71,  23, 100, 100
MOVE G6D, 100, 170,  71,  23, 100, 100
MOVE G6B,  80,  50,  70, 100, 100, 100
MOVE G6C,  80,  50,  70, 100, 100, 100
WAIT

MOVE G6A, 100, 133,  71,  23, 100, 100
MOVE G6D, 100, 133,  71,  23, 100, 100
MOVE G6B,  10,  96,  15, 100, 100, 100
MOVE G6C,  10,  96,  14, 100, 100, 100
WAIT

MOVE G6A, 100, 133,  49,  23, 100, 100
MOVE G6D, 100, 133,  49,  23, 100, 100
MOVE G6B,  45, 116,  15, 100, 100, 100
MOVE G6C,  45, 116,  14, 100, 100, 100
WAIT

MOVE G6A, 100, 133,  49,  23, 100, 100
MOVE G6D, 100,  70, 180, 160, 100, 100
MOVE G6B,  45,  50,  70, 100, 100, 100
MOVE G6C,  45,  50,  70, 100, 100, 100
WAIT

SPEED 15
MOVE G6A, 100, 133, 180, 160, 100, 100
MOVE G6D, 100, 133, 180, 160, 100, 100
MOVE G6B,  10,  50,  70, 100, 100, 100
MOVE G6C,  10,  50,  70, 100, 100, 100
WAIT

HIGHSPEED SETON
MOVE G6A, 100,  95, 180, 160, 100, 100
MOVE G6D, 100,  95, 180, 160, 100, 100
MOVE G6B, 160,  50,  70, 100, 100, 100
MOVE G6C, 160,  50,  70, 100, 100, 100
WAIT

HIGHSPEED SETOFF

MOVE G6A, 100, 130, 120,  80, 110, 100
MOVE G6D, 100, 130, 120,  80, 110, 100
MOVE G6B, 130, 160,  10, 100, 100, 100
MOVE G6C, 130, 160,  10, 100, 100, 100
WAIT
	
GOSUB back_standing

RETURN
'================================================
back_standing:

	SPEED 10
	
	MOVE G6A,100, 130, 120,  80, 110, 100
	MOVE G6D,100, 130, 120,  80, 110, 100
	MOVE G6B,150, 160,  10, 100, 100, 100
	MOVE G6C,150, 160,  10, 100, 100, 100
	WAIT
	
	MOVE G6A, 80, 155,  85, 150, 150, 100
	MOVE G6D, 80, 155,  85, 150, 150, 100
	MOVE G6B,185,  40, 60,  100, 100, 100
	MOVE G6C,185,  40, 60,  100, 100, 100
	WAIT
		
	MOVE G6A, 75, 165,  55, 165, 155, 100
	MOVE G6D, 75, 165,  55, 165, 155, 100
	MOVE G6B,185,  10, 100, 100, 100, 100
	MOVE G6C,185,  10, 100, 100, 100, 100
	WAIT	
	
	MOVE G6A, 60, 165,  30, 165, 155, 100
	MOVE G6D, 60, 165,  30, 165, 155, 100
	MOVE G6B,170,  10, 100, 100, 100, 100
	MOVE G6C,170,  10, 100, 100, 100, 100
	WAIT	
	
	MOVE G6A, 60, 165,  25, 160, 145, 100
	MOVE G6D, 60, 165,  25, 160, 145, 100
	MOVE G6B,150,  60,  90, 100, 100, 100
	MOVE G6C,150,  60,  90, 100, 100, 100
	WAIT	
	
	MOVE G6A,100, 155,  25, 140, 100, 100
	MOVE G6D,100, 155,  25, 140, 100, 100
	MOVE G6B,130,  50,  85, 100, 100, 100
	MOVE G6C,130,  50,  85, 100, 100, 100
	WAIT	

	RETURN
'================================================
'================================================
left_attack:
	SPEED 7
	GOSUB left_attack1
	
	SPEED 12
	HIGHSPEED SETON
	MOVE G6A, 98, 157,  20, 134, 110, 100
	MOVE G6D, 57, 115,  77, 125, 134, 100	
	MOVE G6B,107, 135, 108, 100, 100, 100
	MOVE G6C,112,  92,  99, 100, 100, 100
	WAIT
	DELAY 1000
	HIGHSPEED SETOFF
	SPEED 15
	GOSUB sit_pose
	RETURN
'================================================
left_attack1:
	MOVE G6A,  85,  71, 152,  91, 107, 60  
	MOVE G6D, 108,  76, 145,  93, 100, 60 
	MOVE G6B, 100,  40,  80,  ,  ,  ,
	MOVE G6C, 100,  40,  80,  ,  ,  ,
	WAIT
	RETURN
'================================================
'================================================
right_attack:
	SPEED 7
	GOSUB right_attack1
	
	SPEED 12
	HIGHSPEED SETON
	MOVE G6D, 98, 157,  20, 134, 110, 100
	MOVE G6A, 57, 115,  77, 125, 134, 100
	MOVE G6B,112,  92,  99, 100, 100, 100
	MOVE G6C,107, 135, 108, 100, 100, 100
	WAIT	
	DELAY 1000
	HIGHSPEED SETOFF
	SPEED 15
	GOSUB sit_pose
	RETURN
'================================================
right_attack1:
	MOVE G6D,  85,  71, 152,  91, 107, 60  
	MOVE G6A, 108,  76, 145,  93, 100, 60 
	MOVE G6C, 100,  40,  80,  ,  ,  ,
	MOVE G6B, 100,  40,  80,  ,  ,  ,
	WAIT
	RETURN
'================================================
'================================================
left_forward:
	SPEED 7
	
	MOVE G6A,  85,  71, 152,  91, 107, 60  
	MOVE G6D, 108,  76, 145,  93, 100, 60 
	MOVE G6B, 130,  40,  80,  ,  ,  ,
	MOVE G6C,  70,  40,  80,  ,  ,  ,
	WAIT
	
	SPEED 12
	HIGHSPEED SETON
	
	MOVE G6A, 107, 164,  21, 125,  93
	MOVE G6D,  66, 163,  85,  65, 130	
	MOVE G6B, 189,  40,  77
	MOVE G6C,  50,  72,  86
	WAIT
	
	DELAY 1000
	HIGHSPEED SETOFF
	
	GOSUB sit_pose
	RETURN
	
'================================================
'================================================
right_forward:
	SPEED 7
	MOVE G6D,  85,  71, 152,  91, 107, 60  
	MOVE G6A, 108,  76, 145,  93, 100, 60 	
	MOVE G6C, 130,  40,  80,  ,  ,  ,
	MOVE G6B,  70,  40,  80,  ,  ,  ,
	WAIT
	
	SPEED 10
	HIGHSPEED SETON
	MOVE G6D, 107, 164,  21, 125,  93
	MOVE G6A,  66, 163,  85,  65, 130		
	MOVE G6C, 189,  40,  77
	MOVE G6B,  50,  72,  86
	WAIT
	
	DELAY 1000
	HIGHSPEED SETOFF
	
	GOSUB sit_pose
	RETURN	
'================================================
'================================================
forward_standup:

	SPEED 10
	
	MOVE G6A,100, 130, 120,  80, 110, 100
	MOVE G6D,100, 130, 120,  80, 110, 100
	MOVE G6B,150, 160,  10, 100, 100, 100
	MOVE G6C,150, 160,  10, 100, 100, 100
	WAIT
	
	MOVE G6A, 80, 155,  85, 150, 150, 100
	MOVE G6D, 80, 155,  85, 150, 150, 100
	MOVE G6B,185,  40, 60,  100, 100, 100
	MOVE G6C,185,  40, 60,  100, 100, 100
	WAIT
		
	MOVE G6A, 75, 165,  55, 165, 155, 100
	MOVE G6D, 75, 165,  55, 165, 155, 100
	MOVE G6B,185,  10, 100, 100, 100, 100
	MOVE G6C,185,  10, 100, 100, 100, 100
	WAIT	
	
	MOVE G6A, 60, 165,  30, 165, 155, 100
	MOVE G6D, 60, 165,  30, 165, 155, 100
	MOVE G6B,170,  10, 100, 100, 100, 100
	MOVE G6C,170,  10, 100, 100, 100, 100
	WAIT	
	
	MOVE G6A, 60, 165,  25, 160, 145, 100
	MOVE G6D, 60, 165,  25, 160, 145, 100
	MOVE G6B,150,  60,  90, 100, 100, 100
	MOVE G6C,150,  60,  90, 100, 100, 100
	WAIT	
	
	MOVE G6A,100, 155,  25, 140, 100, 100
	MOVE G6D,100, 155,  25, 140, 100, 100
	MOVE G6B,130,  50,  85, 100, 100, 100
	MOVE G6C,130,  50,  85, 100, 100, 100
	WAIT
	
	GOSUB standard_pose
	
	RETURN
'================================================
'================================================
backward_standup:

	SPEED 10
	
	MOVE G6A,100,  10, 100, 115, 100, 100
	MOVE G6D,100,  10, 100, 115, 100, 100
	MOVE G6B,100, 130,  10, 100, 100, 100
	MOVE G6C,100, 130,  10, 100, 100, 100
	WAIT

	MOVE G6A,100,  10,  83, 140, 100, 100
	MOVE G6D,100,  10,  83, 140, 100, 100
	MOVE G6B, 20, 130,  10, 100, 100, 100
	MOVE G6C, 20, 130,  10, 100, 100, 100
	WAIT

	MOVE G6A,100, 126,  60,  50, 100, 100
	MOVE G6D,100, 126,  60,  50, 100, 100
	MOVE G6B, 20,  30,  90, 100, 100, 100
	MOVE G6C, 20,  30,  90, 100, 100, 100
	WAIT
	
	MOVE G6A,100, 165,  70,  15, 100, 100
	MOVE G6D,100, 165,  70,  15, 100, 100
	MOVE G6B, 30,  20,  95, 100, 100, 100
	MOVE G6C, 30,  20,  95, 100, 100, 100
	WAIT
	
	MOVE G6A,100, 165,  40, 100, 100, 100
	MOVE G6D,100, 165,  40, 100, 100, 100
	MOVE G6B,110,  70,  50, 100, 100, 100
	MOVE G6C,110,  70,  50, 100, 100, 100
	WAIT
	
	GOSUB standard_pose
	RETURN
'=================================================
' cac dong tac nhanh

newfastwalk:

GOSUB newinit

PTP SETOFF
PTP ALLOFF

HIGHSPEED SETON
DIM walkcount AS BYTE
walkcount = 0 


SPEED 5

	MOVE G6A,  99,  74, 145,  93, 101
	MOVE G6D,  99,  74, 145,  93, 101
	WAIT

DELAY 200

	
newfastwalk_1:

	MOVE G6D,  99,  86, 126, 113, 101
	MOVE G6A,  99,  82, 140,  91, 101
	MOVE G6D,  99,  73, 140,  99, 101
	
	MOVE G6A,  99,  86, 128, 112, 101
	MOVE G6D,  99,  82, 140,  92, 101
	MOVE G6A,  99,  73, 140,  99, 101


walkcount = walkcount + 1
IF walkcount < 5 THEN GOTO newfastwalk_1


	MOVE G6D,  94,  92, 126, 119, 101
	MOVE G6D,  99,  70, 140, 103, 101
	
	'????????????????
	MOVE G6A, 99,  76, 145,  93, 101 
	MOVE G6D, 99,  76, 145,  93, 101
	
HIGHSPEED SETOFF	
PTP SETON
PTP ALLON
	
RETURN
'=================================================
fastrightturn:

GOSUB newinit

HIGHSPEED SETON
SPEED 6

	MOVE G6D, 99,  86, 165,  98, 101
	MOVE G6A, 99,  66, 125,  88, 106
	WAIT



	MOVE G6D, 99,  76, 145,  93, 101
	MOVE G6A, 99,  76, 145,  93, 101
	WAIT

HIGHSPEED SETOFF

RETURN


'=================================================

fastleftturn:

GOSUB newinit

HIGHSPEED SETON
SPEED 6

	MOVE G6A, 99,  86, 165,  98, 101
	MOVE G6D, 99,  66, 125,  88, 106
	WAIT
	

	MOVE G6A, 99,  76, 145,  93, 101
	MOVE G6D, 99,  76, 145,  93, 101
	WAIT

HIGHSPEED SETOFF

RETURN

'=================================================
newinit:

DIR G6A,1,0,0,1,0,0		
DIR G6B,1,1,1,1,1,1		
DIR G6C,0,0,0,0,0,0		
DIR G6D,0,1,1,0,1,0		


GETMOTORSET G6A,1,1,1,1,1,0
GETMOTORSET G6B,1,1,1,0,0,0
GETMOTORSET G6C,1,1,1,0,0,0
GETMOTORSET G6D,1,1,1,1,1,0

RETURN
'=================================================

'***************pushup ********************************
'to run the push-ups, run the routine pushup

pushup:
SPEED 10
GOSUB sit2

'lean forward
MOVE G6A, 98, 161,  26, 160, 103, 100
MOVE G6B,180,  17,  98,    ,    ,    
MOVE G6C,177,  20,  91,    ,    ,    
MOVE G6D, 99, 158,  27, 157, 102, 100
	WAIT

'hands down
MOVE G6A,100, 163,  60, 154, 102,    
MOVE G6B,180,  17,  98,    ,    ,    
MOVE G6C,177,  20,  91,    ,    ,    
MOVE G6D,100, 164,  63, 148, 100,    
	WAIT
	
'extend legs
MOVE G6A,100, 61, 157,  74, 105,    

MOVE G6D,100, 61, 167,  68,  99,    
	WAIT

	
FOR i = 0 TO 5
'bend arms
MOVE G6A,100, 61, 157,  74, 105,    
MOVE G6B,180,  89,  11, 100, 100, 100
MOVE G6C,177,  84,  11, 100, 100, 100
MOVE G6D,100, 61, 166,  68,  98, 100
	WAIT

'straighten arms
MOVE G6B,181,  17,  98,    ,    ,    
MOVE G6C,177,  22,  92,    ,    ,    
	WAIT	
NEXT i

GOSUB one_hand_pushup
RETURN

'*********************************************************
'stand up from forward pushup
standup:

'legs out
SPEED 15
MOVE G6A, 76, 165,  54, 162, 156,
MOVE G6B,181,  17,  98,    ,    ,    
MOVE G6C,177,  22,  92,    ,    ,  
MOVE G6D, 76, 165,  54, 162, 156,    
	WAIT


'tilt body back
MOVE G6A, 76, 165,  54, 162, 156, 100
MOVE G6B,163,  17,  98, 100, 100, 100
MOVE G6C,163,  17,  98, 100, 100, 100
MOVE G6D, 76, 165,  54, 162, 156, 100
	WAIT


' lean back for stand up
MOVE G6A, 60, 164,  21, 162, 136,    
MOVE G6B,145,  17,  98, 100, 100, 100
MOVE G6C,145,  17,  98, 100, 100, 100
MOVE G6D, 60, 164,  21, 162, 136,    
	WAIT


GOSUB standard_pose
RETURN

'*******************one hand pushup********************************

one_hand_pushup:

'spread left leg 
MOVE G6A,100,  60, 156, 100, 162, 100

MOVE G6C,160,  13,  88, 100, 100, 100
MOVE G6D,103,  59, 162,  71,  96, 100
	WAIT

'lift left arm
MOVE G6B,181, 169, 178, 100, 100, 100
	WAIT

FOR i = 0 TO 5
'bend arms

MOVE G6C,177,  84,  11, 100, 100, 100
	WAIT

'straighten arms
MOVE G6C,177,  22,  92,    ,    ,    
	WAIT	
NEXT i

'move left arm back
MOVE G6B,180,  17,  98,    ,    ,    
	WAIT
	
GOSUB standup


RETURN


'***************************************
'Sit

Sit2:
MOVE G6A, 97, 156,  26, 130, 102,    
MOVE G6B,100,  96,  99, 100, 100, 100
MOVE G6C,100, 102,  98, 100, 100, 100
MOVE G6D, 97, 161,  27, 128, 104,    
	WAIT
RETURN

'***************************************
begin_pushup:
SPEED 10
GOSUB sit2

'lean forward
MOVE G6A, 98, 161,  26, 160, 103, 100
MOVE G6B,180,  17,  98,    ,    ,    
MOVE G6C,177,  20,  91,    ,    ,    
MOVE G6D, 99, 158,  27, 157, 102, 100
	WAIT

'hands down
MOVE G6A,100, 163,  60, 154, 102,    
MOVE G6B,180,  17,  98,    ,    ,    
MOVE G6C,177,  20,  91,    ,    ,    
MOVE G6D,100, 164,  63, 148, 100,    
	WAIT
	
'extend legs
MOVE G6A,100, 61, 157,  74, 105,    

MOVE G6D,100, 61, 167,  68,  99,    
	WAIT
RETURN

'=================================================

Honor:
    SPEED 3
'Honor thy Master routine written by: Walt Perko for the RoboNova-1 2006.05.26 
'Sit Down
    MOVE G8A,100, 151,  23, 140, 101, 100, 100,  30
    MOVE G8B, 80, 100, 100, 100, 100,  30,  80, 100
    MOVE G8C,100, 100, 100, 151,  23, 140, 101, 100
'Lean Forward
    MOVE G8A,101, 154,  22, 157, 100, 100, 101,  30
    MOVE G8B, 80, 100, 100, 100, 101,  32,  82, 100
    MOVE G8C,100, 100, 100, 156,  23, 154,  97, 100
    DELAY 500
, Extend arms forward
    MOVE G8A,101, 156,  21, 157, 100, 100, 146,  30
    MOVE G8B, 80, 100, 100, 100, 144,  34,  84, 100
    MOVE G8C,100, 100, 101, 156,  23, 155,  95, 100
    DELAY 500
' Fold arms in front
    MOVE G8A,101, 159,  21, 156, 102, 100, 151,  15
    MOVE G8B, 41, 100, 100, 100, 148,  10,  37, 100
    MOVE G8C,100, 100, 101, 160,  23, 155,  94, 100
    DELAY 3000
, Extend arms forward again
    MOVE G8A,101, 156,  21, 157, 100, 100, 146,  30
    MOVE G8B, 80, 100, 100, 100, 144,  34,  84, 100
    MOVE G8C,100, 100, 101, 156,  23, 155,  95, 100
    DELAY 500
'Sit up straight
    MOVE G8A,100, 151,  23, 140, 101, 100, 100,  30
    MOVE G8B, 80, 100, 100, 100, 100,  30,  80, 100
    MOVE G8C,100, 100, 100, 151,  23, 140, 101, 100

' The Power Stand
    MOVE G8A,100,  79, 118, 115,  99, 100, 100,  30
    MOVE G8B, 80, 100, 100, 100, 101,  30,  83, 100
    MOVE G8C,100, 100, 100,  81, 115, 115, 100, 100

    SPEED 10
    MOVE G8A, 93,  76, 145,  94, 109, 100, 100,  35
    MOVE G8B, 90, 100, 100, 100, 100,  35,  90, 100
    MOVE G8C,100, 100,  93,  76, 145,  94, 109, 100
    WAIT
    DELAY 500
'Bicep's
    SPEED 3
    MOVE G8A, 92,  73, 139,  94, 108, 100, 101,  93
    MOVE G8B,154, 100, 100, 100, 102,  90, 159, 100
    MOVE G8C,100, 100,  93,  75, 143,  95, 108, 100
'Tighten UP
    MOVE G8A, 92,  75, 138,  94, 107, 100, 102, 136
    MOVE G8B,189, 100, 100, 100, 103, 146, 187, 100
    MOVE G8C,100, 100,  93,  75, 143,  95, 108, 100
    WAIT
    DELAY 3000

'Bicep's
    SPEED 5
    MOVE G8A, 93,  76, 145,  94, 109, 100, 100,  35
    MOVE G8B, 90, 100, 100, 100, 100,  35,  90, 100
    MOVE G8C,100, 100,  93,  76, 145,  94, 109, 100

    MOVE G8A, 92,  73, 139,  94, 108, 100, 101,  93
    MOVE G8B,154, 100, 100, 100, 102,  90, 159, 100
    MOVE G8C,100, 100,  93,  75, 143,  95, 108, 100
'Tighten UP
    MOVE G8A, 92,  75, 138,  94, 107, 100, 102, 136
    MOVE G8B,189, 100, 100, 100, 103, 146, 187, 100
    MOVE G8C,100, 100,  93,  75, 143,  95, 108, 100

RETURN
'=================================================

BigReach:

	SPEED 10

' Left Hand UP
MOVE G8A,101,  77, 142,  92,  98,  130, 101, 189
MOVE G8B, 99, 100, 100, 100, 102,  33,  83, 100
MOVE G8C,100, 100, 104,  76, 139,  97,  96, 100
    DELAY 500
MOVE G8A,101,  77, 142,  92,  98,  80, 101, 189

    WAIT
    DELAY 500

' Both Hands UP
MOVE G8A,100,  76, 141,  92,  99, 130, 101, 189
MOVE G8B, 99, 100, 100, 100, 102, 187, 100, 100
MOVE G8C,100, 100, 104,  76, 139,  97,  96, 100

    WAIT
    DELAY 500

' Right Hand UP
MOVE G8A,100,  76, 137,  97, 100, 130, 101,  14
MOVE G8B, 99, 100, 100, 100, 102, 187, 100, 100
MOVE G8C,100, 100, 104,  76, 139,  97,  96, 100
    DELAY 500
MOVE G8A,100,  76, 137,  97, 100, 145, 101,  14

    WAIT
    DELAY 500

MOVE G8A,100,  76, 145,  93, 100, 130, 100,  30
MOVE G8B, 80, 100, 100, 100, 100,  30,  80, 100
MOVE G8C,100, 100, 100,  76, 145,  93, 100, 100


RETURN
'=================================================

BigToss:

	SPEED 12
	HIGHSPEED SETON

MOVE G8A,100,  76, 145,  93, 100, 100, 100,  30
MOVE G8B, 80, 100, 100, 100, 189,  39,  82, 100
MOVE G8C,100, 100, 100,  76, 145,  93, 100, 100

MOVE G8A,101,  75, 144,  93,  99, 100, 101,  30
MOVE G8B, 80, 100, 100, 100, 189, 187, 112, 100
MOVE G8C,100, 100, 101,  76, 143,  94,  99, 100

MOVE G8A,101,  75, 143,  94,  98, 100, 101,  30
MOVE G8B, 81, 100, 100, 100, 140, 185, 112, 100
MOVE G8C,100, 100, 102,  76, 142,  95,  98, 100

    SPEED 255

MOVE G8A,101,  74, 142,  94,  98, 100, 101,  30
MOVE G8B, 81, 100, 100, 100, 100, 185, 112, 100
MOVE G8C,100, 100, 103,  76, 140,  96,  98, 100

MOVE G8A, 90,  76, 145,  93, 100, 100, 100,  30
MOVE G8A, 91,  76, 145,  91, 105, 101, 165,  33
MOVE G8C,100, 100, 100,  89, 145,  93, 100, 100

MOVE G8A,101,  73, 141,  94,  98, 100, 102,  30
MOVE G8B, 81, 100, 100, 100,  56, 185, 113, 100
MOVE G8C,100, 100, 103,  76, 139,  97,  98, 100

    SPEED 3
	HIGHSPEED SETOFF

	WAIT
	GOSUB standard_pose

RETURN

'=================================================
Gyro_On: 

GYROSET G6A,0,1,1,0,0,0 
GYROSET G6D,0,1,1,0,0,0 

RETURN 

'=================================================
Gyro_Off: 

GYROSET G6A,0,0,0,0,0,0 
GYROSET G6D,0,0,0,0,0,0 

RETURN 

'(below is the part to copy at the bottom of the Overall Template Program)...

'================================================
'MARTIAL ARTS TEST DEMO (START)
'By: Matt Bauer
'BAUER Independents
'http://www.bauerindependents.com
'nerds@earthlink.net

martial_arts_pose:
HIGHSPEED SETON
SPEED 15
'Martial Arts Pose (MAP) right
MOVE G24, 92, 110, 85, 122, 109, , 100, 177, 163, , , , 100, 88, 132, , , , 60, 61, 162, 94, 130,
HIGHSPEED SETOFF
WAIT
DELAY 500
'MAP transition (slow)
SPEED 3
MOVE G24, 74, 65, 142, 107, 140, , 100, 177, 163, , , , 102, 88, 132, , , , 86, 70, 147, 105, 95,
WAIT
'MAP combo
HIGHSPEED SETON
SPEED 15
MOVE G24, 74, 66, 142, 108, 140, , 189, 92, 97, , , , 158, 23, 50, , , , 89, 69, 144, 106, 91,
WAIT
'rn_4:
MOVE G24, 100, 75, 135, 115, 102, , 145, 115, 71, , , , 160, 102, 60, , , , 99, 68, 142, 117, 97,
WAIT
DELAY 400
'rn_5:
MOVE G24, 103, 64, 113, 156, 98, , 156, 44, 33, , , , 153, 34, 50, , , , 83, 112, 111, 115, 115,
WAIT
HIGHSPEED SETOFF
WAIT
DELAY 800
'MAP transitionraise arms (slow)
SPEED 6
MOVE G24, 94, 83, 98, 137, 99, , 68, 144, 125, , , , 86, 127, 127, , , , 81, 116, 97, 110, 122,
WAIT
'rn_7:
HIGHSPEED SETON
SPEED 15
MOVE G24, 109, 126, 47, 146, 91, , 189, 96, 101, , , , 29, 180, 190, , , , 69, 147, 100, 77, 127,
WAIT
HIGHSPEED SETOFF
WAIT
DELAY 1000
'MAP tranition casual movements
SPEED 4
MOVE G24, 82, 42, 141, 131, 119, , 189, 96, 101, , , , 31, 180, 190, , , , 101, 113, 93, 113, 95,
SPEED 10
MOVE G24, 84, 57, 138, 130, 117, , 160, 24, 58, , , , 157, 38, 75, , , , 99, 63, 126, 138, 95,
WAIT
'MAP transition casual movements
SPEED 4
MOVE G24, 86, 82, 125, 108, 101, , 76, 157, 180, , , , 85, 75, 139, , , , 97, 113, 94, 111, 113,
WAIT
DELAY 300
'MAP left defend pose
RETURN

martial_arts_pose2:
HIGHSPEED SETON
SPEED 14
MOVE G24, 80, 72, 155, 83, 132, , 176, 103, 92, , , , 36, 170, 190, , , , 98, 66, 164, 82, 86,
DELAY 600
WAIT
HIGHSPEED SETOFF
WAIT
'MAP arms up
SPEED 10
MOVE G24, 87, 61, 165, 90, 118, , 109, 159, 131, , , , 100, 141, 122, , , , 106, 53, 188, 75, 87,
WAIT
MUSIC "E" 'as code indicator durring troublshooting
DELAY 200
RETURN

martial_arts_pose3:
'MAP kneel down attack
HIGHSPEED SETON
SPEED 12
MOVE G24, 103, 122, 59, 134, 88, , 177, 34, 45, , , , 187, 74, 73, , , , 60, 120, 103, 93, 146,
WAIT
DELAY 300
'rn_13:
MOVE G24, 116, 111, 61, 156, 87, , 185, 96, 93, , , , 11, 183, 179, , , , 64, 121, 103, 111, 130,
WAIT
DELAY 300
HIGHSPEED SETOFF
WAIT
RETURN
martial_arts_pose4:
'(A) MAP casual defencive pose
SPEED 5
MOVE G24, 92, 85, 104, 125, 93, , 189, 10, 15, , , , 187, 91, 97, , , , 80, 108, 92, 118, 131,
WAIT
'(B) MAP back and fouth ballance movements (linked to previous)
SPEED 3
MOVE G24, 83, 77, 123, 110, 99, , 189, 14, 15, , , , 182, 92, 98, , , , 91, 116, 82, 116, 123,
WAIT
'(C) MAP back and fouth ballance movements (linked to previous)
SPEED 3
MOVE G24, 88, 73, 118, 122, 98, , 181, 14, 15, , , , 180, 87, 98, , , , 87, 101, 90, 126, 124,
WAIT
'(D) MAP back and fouth ballance movements (linked to previous)
MOVE G24, 93, 89, 86, 138, 101, , 181, 14, 15, , , , 170, 88, 95, , , , 79, 104, 83, 129, 123,
WAIT
'(E) MAP back and fouth ballance movements (linked to previous)
MOVE G24, 81, 72, 116, 128, 106, , 190, 10, 15, , , , 187, 97, 101, , , , 92, 105, 76, 138, 115,
WAIT
'(A) MAP back and fouth ballance movements (linked to previous)
MOVE G24, 92, 85, 104, 125, 93, , 189, 10, 15, , , , 187, 91, 97, , , , 80, 108, 92, 118, 131,
WAIT '
'MAP transition casual
SPEED 6
MOVE G24, 108, 86, 103, 129, 90, , 104, 163, 157, , , , 102, 109, 145, , , , 71, 72, 139, 111, 127,
WAIT
RETURN

martial_arts_pose5:
GOSUB map_right_attack 'As found in the default Overall Template Program
DELAY 100
'MAP clap-like sequense
SPEED 15
MOVE G24, 101, 65, 148, 100, 99, , 190, 10, 44, , , , 190, 10, 42, , , , 98, 63, 153, 99, 99,
WAIT
SPEED 8
MOVE G24, 101, 65, 148, 100, 99, , 190, 66, 12, , , , 190, 66, 14, , , , 98, 63, 153, 99, 99,
WAIT

GOSUB standard_pose
WAIT
RETURN


'================================================
'================================================

map_sit_pose:
MOVE G6A, 99, 164, 23, 114, 99
MOVE G6D, 99, 166, 21, 113, 98
MOVE G6B, 170, 55, 45
MOVE G6C, 117, 55, 68
WAIT
RETURN

'================================================
'================================================

map_stand_pose:
MOVE G6A, 98, 78, 111, 131, 100
MOVE G6D, 93, 69, 118, 137, 105
MOVE G6B, 189, 23, 45
MOVE G6C, 174, 26, 71
RETURN
'================================================
'================================================

map_right_attack:
SPEED 7
GOSUB map_right_attack1

HIGHSPEED SETON
SPEED 12
MOVE G6A, 58, 115, 77, 125, 134
MOVE G6D, 93, 157, 20, 134, 110
MOVE G6B, 125, 79, 99
MOVE G6C, 107, 135, 108
WAIT
DELAY 1000
HIGHSPEED SETOFF
SPEED 15
GOSUB map_sit_pose
RETURN
'================================================
map_right_attack1:
MOVE G6D, 85, 71, 152, 91, 107, 60
MOVE G6A, 108, 76, 145, 93, 100, 60
WAIT
RETURN
'================================================
'
'MARTIAL ARTS TEST DEMO (END) 



'================================================ 
' cac dong tac cai tien

'================================================

fast_run:

PTP SETOFF
PTP ALLOFF

HIGHSPEED SETON

SPEED 5

	MOVE G6A,  99,  74, 145,  93, 101
	MOVE G6D,  99,  74, 145,  93, 101
	WAIT

DELAY 200
	
fast_run_1:

	MOVE G6D,  99,  86, 126, 113, 101'rising right foot
	MOVE G6A,  99,  82, 140,  91, 101'rising left foot(reach out right foot)	
	MOVE G6D,  99,  73, 140,  99, 101'take down right foot
		
	MOVE G6A,  99,  86, 128, 112, 101'rising left foot
	MOVE G6D,  99,  82, 140,  92, 101'rear right foot(reach out left foot)
	MOVE G6A,  99,  73, 140,  99, 101'take down left foot


'GOTO fast_run_1						  	

	MOVE G6D,  94,  92, 126, 119, 101'rising right foot
	MOVE G6D,  99,  70, 140, 103, 101'take down right foot
	
	'standard pose
	MOVE G6A, 99,  76, 145,  93, 101 
	MOVE G6D, 99,  76, 145,  93, 101
	
WAIT	
	
RETURN

'================================================
fast_turn_right:
HIGHSPEED SETON
SPEED 6

	MOVE G6D, 99,  86, 165,  98, 101
	MOVE G6A, 99,  66, 125,  88, 106
	WAIT


'standard pose
	MOVE G6D, 99,  76, 145,  93, 101
	MOVE G6A, 99,  76, 145,  93, 101
	WAIT

HIGHSPEED SETOFF
RETURN

'================================================	

fast_turn_left:
HIGHSPEED SETON
SPEED 6

	MOVE G6A, 99,  86, 165,  98, 101
	MOVE G6D, 99,  66, 125,  88, 106
	WAIT
	
'standard pose
	MOVE G6A, 99,  76, 145,  93, 101
	MOVE G6D, 99,  76, 145,  93, 101
	WAIT

HIGHSPEED SETOFF
RETURN

'================================================	

avoid_matrix:
SPEED 10
GOSUB standard_pose

'DELAY 1000
MOVE G6A, 72, 165,  23,  70, 143, 100
MOVE G6D, 72, 165,  23,  70, 143, 100
MOVE G6B,170, 100, 100, 100, 100, 100
MOVE G6C,170, 100, 100, 100, 100, 100


MOVE G6A, 79, 160,  23,  42, 185, 100
MOVE G6D, 79, 160,  23,  42, 185, 100
WAIT

DELAY 4000

SPEED 6
MOVE G6A, 72, 165,  23,  70, 143, 100
MOVE G6D, 72, 165,  23,  70, 143, 100
MOVE G6B,170, 50, 70, 100, 100, 100
MOVE G6C,170, 50, 70, 100, 100, 100
WAIT

MOVE G6A,100, 151,  23, 140, 101, 100
MOVE G6D,100, 151,  23, 140, 101, 100
MOVE G6B,100,  30,  80, , , 
MOVE G6C,100,  30,  80, , , 
WAIT

SPEED 8
GOSUB standard_pose

RETURN

'================================================	

goalkeeper:
SPEED 8
MOVE G6A, 58,  75, 148,  93, 190,  70
MOVE G6D, 58,  75, 148,  93, 190,  70
MOVE G6B,100, 110, 110, 100, 100, 100
MOVE G6C,100, 110, 110, 100, 100, 100
WAIT
DELAY 300

SPEED 5
MOVE G6A, 58,  75, 148,  30, 150,  70
MOVE G6D, 58,  75, 148,  30, 150,  70
MOVE G6B, 100, 180, 140, 100, 100, 100
MOVE G6C, 100, 180, 140, 100, 100, 100
WAIT
SPEED 10
DELAY 300
GOSUB standard_pose
GOSUB backward_standup
RETURN


'backward_standup:

'	SPEED 10
	
'	MOVE G6A,100, 130, 120,  80, 110, 100
'	MOVE G6D,100, 130, 120,  80, 110, 100
'	MOVE G6B,150, 160,  10, 100, 100, 100
'	MOVE G6C,150, 160,  10, 100, 100, 100
'	WAIT
'	
'	MOVE G6A, 80, 155,  85, 150, 150, 100
'	MOVE G6D, 80, 155,  85, 150, 150, 100
'	MOVE G6B,185,  40, 60,  100, 100, 100
'	MOVE G6C,185,  40, 60,  100, 100, 100
'	WAIT
'	
''	MOVE G6A, 75, 165,  55, 165, 155, 100
'	MOVE G6D, 75, 165,  55, 165, 155, 100
'	MOVE G6B,185,  10, 100, 100, 100, 100
''	MOVE G6C,185,  10, 100, 100, 100, 100
'	WAIT
''	
'	MOVE G6A, 60, 165,  30, 165, 155, 100
'	MOVE G6D, 60, 165,  30, 165, 155, 100
'	MOVE G6B,170,  10, 100, 100, 100, 100
''	MOVE G6C,170,  10, 100, 100, 100, 100
'	WAIT
'	
''	MOVE G6A, 60, 165,  25, 160, 145, 100
'	MOVE G6D, 60, 165,  25, 160, 145, 100
'	MOVE G6B,150,  60,  90, 100, 100, 100
'	MOVE G6C,150,  60,  90, 100, 100, 100
'	WAIT
'	
'	MOVE G6A,100, 155,  25, 140, 100, 100
'	MOVE G6D,100, 155,  25, 140, 100, 100
'	MOVE G6B,130,  50,  85, 100, 100, 100
'	MOVE G6C,130,  50,  85, 100, 100, 100
'	WAIT
'	
'	GOSUB standard_pose
'	
'	RETURN

'================================================	

cheer_up:

	
	SPEED 10
	MOVE G6A,100,  80, 167,  50, 100, 100
	MOVE G6D,100,  80, 167,  50, 100, 100
	MOVE G6B,100, 145, 125, , , 
	MOVE G6C,100, 145, 122, , , 
	WAIT
	
	FOR I = 0 TO 1
	MOVE G6B,100, 100, 140, , , , 
	MOVE G6C,100, 100, 140, , , , 
	WAIT
	MOVE G6B,100, 165, 160, , , , 
	MOVE G6C,100, 165, 160, , , , 
	WAIT
	
	NEXT I
	SPEED 8
	DELAY 200
	GOSUB standard_pose
	
	RETURN



'================================================	

single_foot_standing:
SPEED 5
MOVE G6A,113,  56, 182,  75,  90, 60
MOVE G6D, 73,  56, 182,  75, 116, 60
MOVE G6B,100, 100, 100, 100, 100, 100
MOVE G6C,100,  40,  90, 100, 100, 100
WAIT

MOVE G6A,114,  56, 181,  75, 90, 100
MOVE G6D, 80, 155,  23, 135, 117, 100
MOVE G6B,100, 110, 100, 100, 100, 100
MOVE G6C,100, 110, 100, 100, 100, 100
WAIT
SPEED 2
MOVE G6A,108,  56, 181,  75, 133, 100
MOVE G6D, 80, 155,  23, 135, 155, 100
MOVE G6B,100, 140, 100, 100, 100, 100
MOVE G6C,100, 154, 100, 100, 100, 100
WAIT
DELAY 200
SPEED 2
MOVE G6A,110,  56, 181,  75, 133, 100
MOVE G6D,100,  59, 170,  85, 155, 100
MOVE G6B,100, 105, 100, 100, 100, 100
MOVE G6C,100, 154, 100, 100, 100, 100
WAIT

DELAY 1000
SPEED 10
FOR i = 0 TO 5
MOVE G6C,100, 174, 100, 100, 100, 100
WAIT
MOVE G6C,100, 134, 100, 100, 100, 100
WAIT
NEXT i
DELAY 3000
SPEED 3
MOVE G6A,110,  56, 181,  75, 133, 100
MOVE G6D, 80, 155,  23, 135, 155, 100
MOVE G6B,100, 110, 100, 100, 100, 100
MOVE G6C,100, 154, 100, 100, 100, 100
WAIT

DELAY 1000
MOVE G6A,114,  56, 181,  75, 90, 60
MOVE G6D, 80, 155,  23, 135, 117, 60
MOVE G6B,100, 120, 100, 100, 100, 100
MOVE G6C,100, 170, 100, 100, 100, 100
WAIT
SPEED 10
MOVE G6A,114,  56, 182,  75,  90, 100
MOVE G6D, 73,  56, 182,  75, 116, 100
MOVE G6B,100, 120, 100, 100, 100, 100
MOVE G6C,100,  40,  90, 100, 100, 100
WAIT

GOSUB standard_pose

RETURN

'================================================	

hand_clapping:

	SPEED 10
	WAIT

	HIGHSPEED SETON

	MOVE G6C, 145, 20, 70,  ,  ,  ,
	MOVE G6B, 145, 20, 70,  ,  ,  , 

	FOR a = 0 TO 3	
	MOVE G6C, 145, 20, 40,  ,  ,  ,
	MOVE G6B, 145, 20, 40,  ,  ,  , 	
	WAIT
	
	MOVE G6C, 145, 15, 25,  ,  ,  ,
	MOVE G6B, 145, 15, 25,  ,  ,  , 	
	WAIT
	
	MOVE G6C, 145, 20, 40,  ,  ,  ,
	MOVE G6B, 145, 20, 40,  ,  ,  , 	
	WAIT
	DELAY 100
	
	MOVE G6C, 145, 15, 25,  ,  ,  ,
	MOVE G6B, 145, 15, 25,  ,  ,  , 	
	WAIT
	
	MOVE G6C, 155, 20, 40,  ,  ,  ,
	MOVE G6B, 155, 20, 40,  ,  ,  , 	
	WAIT
	DELAY 100
	
	MOVE G6C, 155, 15, 25,  ,  ,  ,
	MOVE G6B, 155, 15, 25,  ,  ,  , 	
	WAIT

	MOVE G6C, 155, 20, 40,  ,  ,  ,
	MOVE G6B, 155, 20, 40,  ,  ,  , 	
	WAIT
		
	DELAY 400
	NEXT a
	
	MOVE G6C, 145, 20, 70,  ,  ,  ,
	MOVE G6B, 145, 20, 70,  ,  ,  , 	
	
	HIGHSPEED SETOFF
	RETURN	

'================================================	


hand_shaking:

	SPEED 10
	WAIT

	HIGHSPEED SETON

	MOVE G6C, 190, 100, 100,  ,  ,  ,
	MOVE G6B, 190, 100, 100,  ,  ,  , 

	FOR a = 0 TO 3	
	MOVE G6C, 190, 100, 100,  ,  ,  ,
	MOVE G6B, 190, 45, 45,  ,  ,  , 	
	WAIT
	DELAY 200
	
	MOVE G6C, 190, 45, 45,  ,  ,  ,
	MOVE G6B, 190, 100, 100,  ,  ,  , 	
	WAIT
	DELAY 200
	NEXT a
	
	
	HIGHSPEED SETOFF
	RETURN			

'================================================	

break_dance:

GOSUB front_lie_down
SPEED 6
MOVE G6A,100, 125,  65,  10, 100  
MOVE G6D,100, 125,  65,  10, 100 
MOVE G6B, 110,  30,  80,  ,  ,  , 
MOVE G6C,110,  30,  80,  ,  ,  , 
 

SPEED 3
MOVE G6A,100, 125,  65,  10, 100,  
MOVE G6D, 100, 125,  65,  10, 100 
MOVE G6B, 170,  30,  80,  ,  ,  ,
MOVE G6C, 170,  30,  80,  ,  ,  , 
WAIT

DELAY 200
SPEED 6
MOVE G6A,100,  89, 129,  57, 100,  
MOVE G6D, 100,  89, 129,  57, 100 
MOVE G6B, 180,  30,  80,  ,  ,  ,
MOVE G6C, 180,  30,  80,  ,  ,  , 

WAIT

MOVE G6A,100,  64, 179,  57, 100,  
MOVE G6D, 100,  64, 179,  57, 100 
MOVE G6B, 190,  50,  80,  ,  ,  ,
MOVE G6C, 190,  50,  80,  ,  ,  , 
WAIT
DELAY 500

MOVE G6A,100,  64, 179,  57, 160,  
MOVE G6D, 100,  64, 179,  57, 160 
WAIT

DELAY 1000

SPEED 3
MOVE G6A,100,  64, 179,  17, 160,  
MOVE G6D, 100,  64, 179,  97, 160 
WAIT

DELAY 1000

MOVE G6A,100,  64, 179,  97, 160,  
MOVE G6D, 100,  64, 179,  17, 160 
WAIT

DELAY 1000


MOVE G6A,100,  64, 179,  57, 160,  
MOVE G6D, 100,  64, 179,  57, 160 
WAIT
DELAY 500
SPEED 7

MOVE G6A,100,  64, 179,  57, 100  
MOVE G6D,100,  64, 179,  57, 100  
WAIT

MOVE G6A,100,  64, 179,  57, 190  
MOVE G6D,100,  64, 179,  57, 190  
WAIT

MOVE G6A,100,  64, 179,  57, 100  
MOVE G6D,100,  64, 179,  57, 100  
WAIT
DELAY 1000

MOVE G6B, 190,  50,  80,  ,  ,  , 
MOVE G6C,190,  50,  80,  ,  ,  , 
WAIT

MOVE G6A,100,  89, 129,  57, 100,  
MOVE G6D,100,  89, 129,  57, 100  
MOVE G6B, 180,  30,  80,  ,  ,  ,
MOVE G6C, 180,  30,  80,  ,  ,  , 
WAIT

SPEED 3
MOVE G6A,100, 125,  65,  10, 100,  
MOVE G6D, 100, 125,  65,  10, 100  
MOVE G6B, 170,  30,  80,  ,  ,  ,
MOVE G6C, 170,  30,  80,  ,  ,  , 
WAIT

SPEED 6
MOVE G6A,100, 125,  65,  10, 100,  
MOVE G6D, 100, 125,  65,  10, 100 
MOVE G6B, 110,  30,  80,  ,  ,  ,
MOVE G6C, 110,  30,  80,  ,  ,  , 
WAIT
 
GOSUB standard_pose 

GOSUB back_raise


RETURN


back_raise:
	SPEED 10
	'GOSUB ????????????
	
	MOVE G6A,100, 130, 120,  80, 110, 100
	MOVE G6D,100, 130, 120,  80, 110, 100
	MOVE G6B,150, 160,  10, 100, 100, 100
	MOVE G6C,150, 160,  10, 100, 100, 100
	WAIT
	
	MOVE G6A, 80, 155,  85, 150, 150, 100
	MOVE G6D, 80, 155,  85, 150, 150, 100
	MOVE G6B,185,  40, 60,  100, 100, 100
	MOVE G6C,185,  40, 60,  100, 100, 100
	WAIT
	
	MOVE G6A, 75, 165,  55, 165, 155, 100
	MOVE G6D, 75, 165,  55, 165, 155, 100
	MOVE G6B,185,  10, 100, 100, 100, 100
	MOVE G6C,185,  10, 100, 100, 100, 100
	WAIT
	
	MOVE G6A, 60, 165,  30, 165, 155, 100
	MOVE G6D, 60, 165,  30, 165, 155, 100
	MOVE G6B,170,  10, 100, 100, 100, 100
	MOVE G6C,170,  10, 100, 100, 100, 100
	WAIT
	
	MOVE G6A, 60, 165,  25, 160, 145, 100
	MOVE G6D, 60, 165,  25, 160, 145, 100
	MOVE G6B,150,  60,  90, 100, 100, 100
	MOVE G6C,150,  60,  90, 100, 100, 100
	WAIT
	
	MOVE G6A,100, 155,  25, 140, 100, 100
	MOVE G6D,100, 155,  25, 140, 100, 100
	MOVE G6B,130,  50,  85, 100, 100, 100
	MOVE G6C,130,  50,  85, 100, 100, 100
	WAIT
	'DELAY 100
	
	GOSUB standard_pose 
	
	RETURN


front_lie_down:

	SPEED 10
	MOVE G6A,100, 155,  25, 140, 100, 100
	MOVE G6D,100, 155,  25, 140, 100, 100
	MOVE G6B,130,  50,  85, 100, 100, 100
	MOVE G6C,130,  50,  85, 100, 100, 100
	WAIT
	
	MOVE G6A, 60, 165,  25, 160, 145, 100
	MOVE G6D, 60, 165,  25, 160, 145, 100
	MOVE G6B,150,  60,  90, 100, 100, 100
	MOVE G6C,150,  60,  90, 100, 100, 100
	WAIT
	
	MOVE G6A, 60, 165,  30, 165, 155, 100
	MOVE G6D, 60, 165,  30, 165, 155, 100
	MOVE G6B,170,  10, 100, 100, 100, 100
	MOVE G6C,170,  10, 100, 100, 100, 100
	WAIT
	SPEED 3

	
	MOVE G6A, 75, 165,  55, 165, 155, 100
	MOVE G6D, 75, 165,  55, 165, 155, 100
	MOVE G6B,185,  10, 100, 100, 100, 100
	MOVE G6C,185,  10, 100, 100, 100, 100
	WAIT
	SPEED 10

	
	MOVE G6A, 80, 155,  85, 150, 150, 100
	MOVE G6D, 80, 155,  85, 150, 150, 100
	MOVE G6B,185,  40, 60,  100, 100, 100
	MOVE G6C,185,  40, 60,  100, 100, 100
	WAIT
		
	MOVE G6A,100, 130, 120,  80, 110, 100
	MOVE G6D,100, 130, 120,  80, 110, 100
	MOVE G6B,125, 160,  10, 100, 100, 100
	MOVE G6C,125, 160,  10, 100, 100, 100
	WAIT	
	
	GOSUB standard_pose
	
	RETURN

'-------------------------------------

dance1:

	SPEED 15
	WAIT

	FOR a = 0 TO 2
	MOVE G6A, 85,  76, 145,  93, 100, 100
	MOVE G6D, 85,  76, 145,  93, 100, 100
	MOVE G6B, 100, 55, 55,  ,  ,  ,
	MOVE G6C, 100, 55, 55,  ,  ,  , 
	WAIT

	MOVE G6D, 100,  76, 145,  93, 100, 100
	MOVE G6A, 100,  76, 145,  93, 100, 100
	MOVE G6C, 100, 45, 65,  ,  ,  ,
	MOVE G6B, 100, 45, 65,  ,  ,  , 
	WAIT
	DELAY 100
	NEXT a
	
	DELAY 200
	
	FOR a = 0 TO 2
	MOVE G6A, 85,  76, 145,  93, 100, 100
	MOVE G6D, 85,  76, 145,  93, 100, 100
	MOVE G6B, 100, 55, 55,  ,  ,  ,
	MOVE G6C, 100, 55, 55,  ,  ,  , 
	WAIT

	MOVE G6D, 100,  76, 145,  93, 100, 100
	MOVE G6A, 100,  76, 145,  93, 100, 100
	MOVE G6C, 100, 45, 65,  ,  ,  ,
	MOVE G6B, 100, 45, 65,  ,  ,  , 
	WAIT
	DELAY 100
	NEXT a
	
	FOR a = 0 TO 2
	MOVE G6A, 85,  76, 145,  93, 100, 100
	MOVE G6D, 85,  76, 145,  93, 100, 100
	MOVE G6B, 100, 55, 55,  ,  ,  ,
	MOVE G6C, 100, 55, 55,  ,  ,  , 
	WAIT

	MOVE G6D, 100,  76, 145,  93, 100, 100
	MOVE G6A, 100,  76, 145,  93, 100, 100
	MOVE G6C, 100, 45, 65,  ,  ,  ,
	MOVE G6B, 100, 45, 65,  ,  ,  , 
	WAIT
	DELAY 100
	NEXT a
	
	DELAY 200


	RETURN	

'================================================		
	
sit_position:
	SPEED 10
	MOVE G6A,100, 151,  27, 140, 100, 100
	MOVE G6D,100, 151,  27, 140, 100, 100
	MOVE G6B,100,  30,  80, , , 
	MOVE G6C,100,  30,  80, , , 
	WAIT
	
	MOVE G6A,100, 151,  23, 140, 101, 100
	MOVE G6D,100, 151,  23, 140, 101, 100
	MOVE G6B,100,  30,  80, , , 
	MOVE G6C,100,  30,  80, , , 
	WAIT
	
	RETURN

'================================================	


dance2:

	SPEED 15

	FOR a = 0 TO 2
	MOVE G6A,101,  76, 145,  93, 100, 100
	MOVE G6D, 99,  76, 145,  93, 100, 102
	MOVE G6B, 100, 145, 180,  ,  ,  ,
	MOVE G6C, 100, 100, 145,  ,  ,  , 
	WAIT

	MOVE G6D,101,  76, 145,  93, 100, 100
	MOVE G6A, 99,  76, 145,  93, 100, 102
	MOVE G6C, 100, 145, 180,  ,  ,  ,
	MOVE G6B, 100, 120, 145,  ,  ,  , 
	WAIT
		DELAY 100
	NEXT a
	
	DELAY 100
	
	FOR a = 0 TO 2
	MOVE G6A,101,  76, 145,  93, 100, 100
	MOVE G6D, 99,  76, 145,  93, 100, 102
	MOVE G6B, 100, 145, 180,  ,  ,  ,
	MOVE G6C, 100, 120, 145,  ,  ,  , 
	WAIT

	MOVE G6D,101,  76, 145,  93, 100, 100
	MOVE G6A, 99,  76, 145,  93, 100, 102
	MOVE G6C, 100, 145, 180,  ,  ,  ,
	MOVE G6B, 100, 120, 145,  ,  ,  , 
		DELAY 100
	WAIT
	NEXT a
	
	DELAY 100
	
	FOR a = 0 TO 2
	MOVE G6A,101,  76, 145,  93, 100, 100
	MOVE G6D, 99,  76, 145,  93, 100, 102
	MOVE G6B, 100, 145, 180,  ,  ,  ,
	MOVE G6C, 100, 120, 145,  ,  ,  , 
	WAIT

	MOVE G6D,101,  76, 145,  93, 100, 100
	MOVE G6A, 99,  76, 145,  93, 100, 102
	MOVE G6C, 100, 145, 180,  ,  ,  ,
	MOVE G6B, 100, 120, 145,  ,  ,  , 
	WAIT
	NEXT a	
	
	RETURN

'================================================	

dance3:
MOVE G6A, 87, 120,  73, 130, 112, 100
MOVE G6D, 87, 120,  73, 130, 112, 100
MOVE G6B,102, 100, 100, 100, 100, 100
MOVE G6C,102, 100, 100, 100, 100, 100
WAIT
DELAY 1000
SPEED 5

FOR i = 0 TO 1
MOVE G6A,117, 166,  22, 130, 133, 100
MOVE G6D, 63,  77, 138, 102,  89, 100
WAIT
DELAY 500

MOVE G6A, 87, 120,  73, 130, 112, 100
MOVE G6D, 87, 120,  73, 130, 112, 100
WAIT
DELAY 500

MOVE G6A, 63,  77, 138, 102,  89, 100
MOVE G6D,117, 166,  22, 130, 133, 100
WAIT
DELAY 500

MOVE G6A, 87, 120,  73, 130, 112, 100
MOVE G6D, 87, 120,  73, 130, 112, 100
WAIT
DELAY 500

NEXT i
SPEED 5


MOVE G6A, 87, 120,  73, 125, 112, 100
MOVE G6D, 87, 120,  73, 125, 112, 100
WAIT
DELAY 500

SPEED 10

MOVE G6A, 100,  62, 165,  90, 100, 100
MOVE G6D, 100,  62, 165,  90, 100, 100
MOVE G6B,102,  30,  80, 100, 100, 100
MOVE G6C,102,  30,  80, 100, 100, 100


SPEED 10

GOSUB standard_pose
RETURN

'================================================	

sit_forward_walking:
	SPEED 10
	MOVE G6B,100,  35,  80, 100, 100, 100
	MOVE G6C,100,  35,  80, 100, 100, 100
	WAIT
	
	FOR I = 0 TO 3
	
	MOVE G6A,115, 150,  24, 140,  94, 100
	MOVE G6D, 86, 151,  26, 140, 110, 100
	WAIT
	
	MOVE G6A,100, 160,  25, 133, 100, 100
	MOVE G6D,100, 131,  26, 162, 100, 100
	WAIT
	
	MOVE G6A, 86, 151,  26, 140, 110, 100
	MOVE G6D,115, 150,  24, 140,  94, 100
	WAIT
	
	MOVE G6A,100, 131,  26, 162, 100, 100
	MOVE G6D,100, 160,  25, 133, 100, 100
	WAIT
	
	NEXT I
	
	SPEED 8
	MOVE G6A,115, 150,  24, 140,  94, 100
	MOVE G6D, 86, 151,  26, 140, 110, 100
	WAIT
	
	MOVE G6A,100, 151,  23, 140, 101, 100
	MOVE G6D,100, 151,  23, 140, 101, 100
	WAIT
	
	RETURN
	
'================================================	

sit_backward_walking:
	SPEED 10
	MOVE G6B,100,  35,  80, 100, 100, 100
	MOVE G6C,100,  35,  80, 100, 100, 100
	WAIT
	
	FOR I = 0 TO 3
	
	MOVE G6A,115, 150,  24, 140,  94, 100
	MOVE G6D, 86, 151,  26, 140, 110, 100
	WAIT
	
	MOVE G6A,100, 131,  26, 162, 100, 100
	MOVE G6D,100, 160,  25, 133, 100, 100
	WAIT
	
	
	MOVE G6A, 86, 151,  26, 140, 110, 100
	MOVE G6D,115, 150,  24, 140,  94, 100
	WAIT
	
	MOVE G6A,100, 160,  25, 133, 100, 100
	MOVE G6D,100, 131,  26, 162, 100, 100
	WAIT
	
	NEXT I
	
	SPEED 8
	MOVE G6A,115, 150,  24, 140,  94, 100
	MOVE G6D, 86, 151,  26, 140, 110, 100
	WAIT
	
	MOVE G6A,100, 151,  23, 140, 101, 100
	MOVE G6D,100, 151,  23, 140, 101, 100
	WAIT
	RETURN

'================================================
sit_right_walking:
	SPEED 8
	MOVE G6A, 86, 151,  23, 140, 105, 100
	MOVE G6D,112, 150,  23, 140, 100, 100
	MOVE G6B,100,  40,  75, 100, 100, 100
	MOVE G6C,100,  40,  75, 100, 100, 100
	WAIT
	
	MOVE G6A, 86, 151,  26, 140, 115, 100
	MOVE G6D, 86, 151,  26, 140, 115, 100
	WAIT
	
	'SPEED 10
	MOVE G6A,118, 154,  24, 140, 95, 100
	MOVE G6D, 80, 154,  24, 140, 110, 100
	'MOVE G6B,100,  70,  75, 100, 100, 100
	WAIT
	
	SPEED 8
	MOVE G6A,100, 151,  23, 140, 101, 100
	MOVE G6D,100, 151,  23, 140, 101, 100
	MOVE G6B,100,  30,  80, , , 
	MOVE G6C,100,  30,  80, , , 
	WAIT
	
	RETURN
	
'================================================

sit_left_walking:
	SPEED 8 
	MOVE G6A,112, 150,  24, 140, 100, 100
	MOVE G6D, 86, 151,  24, 140, 105, 100
	MOVE G6B,100,  40,  75, 100, 100, 100
	MOVE G6C,100,  40,  75, 100, 100, 100
	WAIT
	
	MOVE G6A, 86, 150,  24, 140, 115, 100
	MOVE G6D, 86, 151,  24, 140, 115, 100
	WAIT
	
	MOVE G6A, 86, 151,  24, 140, 105, 100
	MOVE G6D,115, 150,  24, 140, 100, 100
	WAIT
	
	SPEED 5
	GOSUB sit_position
	RETURN	
	
	
'================================================

push_up:	
	
MOVE G6A,101, 164,  23, 168, 100, 100
MOVE G6B,159,  30,  81, 100, 100, 100
MOVE G6C,160,  30,  81, 100, 100, 100
MOVE G6D,100, 167,  20, 169,  99, 100



FOR i=0 TO 10


MOVE G6A,101,  74, 139,  98,  96, 100
MOVE G6B,182,  77,  12, 100, 100, 100
MOVE G6C,174,  97,  25, 100, 100, 100
MOVE G6D,107,  74, 127, 105, 103, 100



MOVE G6A,101,  74, 139,  98,  96, 100
MOVE G6B,171,  12, 100, 100, 100, 100
MOVE G6C,170,  10,  99, 100, 100, 100
MOVE G6D,107,  74, 127, 105, 103, 100


	
	
MOVE G6A,101,  74, 139,  98,  96, 100
MOVE G6B,182,  77,  12, 100, 100, 100
MOVE G6C,174,  97,  25, 100, 100, 100
MOVE G6D,107,  74, 127, 105, 103, 100
	
	
NEXT i	

WAIT

RETURN

'================================================
upstair:

SPEED 3
MOVE G24,  85,  75, 145,  93, 115,  , 100,  30,  80,  ,  ,  , 100,  30,  80,  ,  ,  , 115,  75, 145,  93,  85,  

SPEED 5
MOVE G24,  82, 115,  65, 133, 118,  , 100,  30,  80,  ,  ,  , 100,  30,  80,  ,  ,  , 115,  75, 145,  93,  85,  
MOVE G24,  90,  85,  75, 153, 110,  , 100,  30,  80,  ,  ,  , 100,  30,  80,  ,  ,  , 115,  75, 145,  93,  85,  
MOVE G24,  90,  55, 105, 163, 110,  , 100,  30,  80,  ,  ,  , 100,  30,  80,  ,  ,  , 115,  75, 145,  93,  85,  
MOVE G24, 100,  15, 145, 153, 105,  , 100,  30,  80,  ,  ,  , 100,  30,  80,  ,  ,  , 115,  75, 145,  93,  85,  
MOVE G24, 100,  15, 145, 153, 105,  , 100,  30,  80,  ,  ,  , 100,  30,  80,  ,  ,  , 110,  95, 125,  93,  90,  

DELAY 100

SPEED 4
MOVE G24, 115, 115,  45, 148,  85,  , 100,  30,  80,  ,  ,  , 100,  30,  80,  ,  ,  ,  85, 110, 170,  20, 115,  
MOVE G24, 115, 125,  75, 128,  85,  , 100,  30,  80,  ,  ,  , 100,  30,  80,  ,  ,  ,  85,  70, 175,  40, 115,  

DELAY 100

SPEED 5
MOVE G24, 115,  75, 145, 113,  85,  , 100,  30,  80,  ,  ,  , 100,  30,  80,  ,  ,  ,  85, 110, 175,  20, 115,  
MOVE G24, 115,  75, 145, 113,  85,  , 100,  30,  80,  ,  ,  , 100,  30,  80,  ,  ,  ,  85, 110,  95, 100, 115,  
MOVE G24, 115,  75, 145, 103,  85,  , 100,  30,  80,  ,  ,  , 100,  30,  80,  ,  ,  ,  85,  98, 105, 120, 115,  

MOVE G24, 115,  75, 145,  93,  85,  , 100,  30,  80,  ,  ,  , 100,  30,  80,  ,  ,  ,  85,  75, 145,  93, 115,  
	
SPEED 2

MOVE G24, 100,  75, 145,  93, 100,  , 100,  45,  70,  ,  ,  , 100,  45,  70,  ,  ,  , 100,  75, 145,  93, 100,  
MOVE G24, 100,  76, 145,  93, 100,  , 100,  30,  80,  ,  ,  , 100,  30,  80,  ,  ,  , 100,  76, 145,  93, 100,  

GOSUB standard_pose
RETURN	

'================================================	


'================================================
' CAC CHUONG TRINH CON DOC CAM BIEN & PHAN XA MINA
'================================================
read_sensors_only:
	IF US_USE_AD = 0 THEN
		US_RAW = SONAR(US_PORT)
	ENDIF
	IF US_USE_AD = 1 THEN
		US_RAW = AD(US_AD_PORT)
	ENDIF
	US_HI = US_RAW / 256
	US_LO = US_RAW MOD 256
	DIST_10K = AD(DIST_AD_PORT)
	BATT_RAW = AD(6)
	TILT_RAW = AD(5)
	CHK_SUM = US_HI
	CHK_SUM = CHK_SUM + US_LO
	CHK_SUM = CHK_SUM + DIST_10K
	CHK_SUM = CHK_SUM + BATT_RAW
	CHK_SUM = CHK_SUM + TILT_RAW
	CHK_BYTE = CHK_SUM MOD 256
	RETURN

'================================================
read_and_send_sensors:
	GOSUB read_sensors_only
	BTOut = 170
	ETX 9600, BTOut
	BTOut = 85
	ETX 9600, BTOut
	BTOut = US_HI
	ETX 9600, BTOut
	BTOut = US_LO
	ETX 9600, BTOut
	BTOut = DIST_10K
	ETX 9600, BTOut
	BTOut = BATT_RAW
	ETX 9600, BTOut
	BTOut = TILT_RAW
	ETX 9600, BTOut
	BTOut = CHK_BYTE
	ETX 9600, BTOut
	RETURN

'================================================
check_front_obstacle:
	OBS_HIT = 0
	GOSUB read_sensors_only
	IF US_RAW > 0 AND US_RAW < US_LIMIT THEN
		OBS_HIT = 1
	ENDIF
	IF DIST_10K > DIST10K_LIMIT THEN
		OBS_HIT = 1
	ENDIF
	RETURN

'================================================
avoid_obstacle_step:
	TEMPO 230
	MUSIC "GE"
	GOSUB read_and_send_sensors
	GOSUB backward_walk
	GOSUB standard_pose
	RETURN

'================================================
robot_tilt_auto:
	IF TILT_ON = 0 THEN RETURN
	A = AD(5)
	IF A = 0 THEN RETURN
	IF A > 250 THEN RETURN
	IF A > 2 AND A < 30 THEN
		DELAY 150
		A = AD(5)
		IF A > 2 AND A < 30 THEN
			GOSUB backward_standup
			GOSUB standard_pose
		ENDIF
	ENDIF
	IF A > 200 AND A <= 250 THEN
		DELAY 150
		A = AD(5)
		IF A > 200 AND A <= 250 THEN
			GOSUB forward_standup
			GOSUB standard_pose
		ENDIF
	ENDIF
	RETURN
'================================================
