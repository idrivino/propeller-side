' /////////////////////////////////////////////////////////////////////////////
{ 
 cham_default2_drv_112.spin
 AUTHOR: Andre' LaMothe
 LAST MODIFIED: 9/29/09
 VERSION 1.12

 COMMENTS: This is the Chameleon generic driver "Default 2". It's not meant to be fast or sexy, but simple a
 good example of interfacing to multiple drivers on the Propeller chip. This version of the driver "Default 2", uses
 my HEL tile engine to augment the graphics on the NTSC screen and give you more "gaming" opportunities. Other than that
 this driver is the same as the "Default1" driver. This driver simply has more commands. Howevedr, the same simple Terminal I/O
 commands that work on the NTSC Default driver work here. Thus, as long as you don't need more than 32x24 characters on the screen
 you should use the higher performance Default2 version. But, bottom line is you can use any objects you want and make you own drivers
 these are just examples! Also, starting with version 1.12, we have pulled the SPI driver out into its own source file as well as adding some
 command completion logic, so the client doesn't have to rely on time delays to "wait" for commands to finish. With the new system after you
 issue a command, if you try to issue another, it will block until the previous command is complete. 
 

 This drivers supports the following capabilities:

 0. COG 0 - runs SPI channel message dispatch and MCP (master control program).
 1. COG 1 - runs ASSEMBLY language "virtual" SPI interface that AVR/PIC communicates with.
 2. NTSC video (1 COG) - simple "terminal" or more advanced graphics tile engine.
 3. VGA video (1 COG).
 4. Multi-channel audio (1 COG).
 5. Keyboard or mouse (0/1 COG).
 6. I/O to the Propeller "Local" I/O 8-bit port. (Uses COG 0, runs in main thread for now).

 Total COGS 5-6
 
 From the AVR/PIC side you can write a lot of interesting programs that leverage these simple drivers, then as your needs change
 follow the documentation tutorial on how to modify this driver, so you can alter and enhance its functionality and try different "Objects"
 from the Parallax Object Exchange or other sources. 

 ARCHITECTURAL OVERVIEW:  This system works by the host (AVR/PIC) sending commands over the SPI interface to the virtual
 SPI driver running (launched by this object), then as commands come thru the SPI data stream they are parsed and dispatched
 to the proper drivers running on other COGS. Here's a visual of what's going on:

  AVR/PIC  <--------> SPI <-----------> Prop (virtual SPI Interface ASM language)
                                                  |   |   |   |   |  
                                                  |   |   |   |   |--NTSC driver -----> TV monitor
                                                  |   |   |   |
                                                  |   |   |   |------VGA driver  -----> VGA monitor
                                                  |   |   |   
                                                  |   |   |----------Keyboard driver -> PS/2 keyboard
                                                  |   |
                                                  |   |--------------Mouse driver ----> PS/2 mouse
                                                  |
                                                  |------------------Sound driver ----> Audio amp or TV
                                                                        .
                                                                        .
                                                                        . (more drivers)
}
' ///////////////////////////////////////////////////////////////////////////



'//////////////////////////////////////////////////////////////////////////////
' CONSTANTS SECTION ///////////////////////////////////////////////////////////
'//////////////////////////////////////////////////////////////////////////////

CON

  ' These settings are for 5 MHZ XTALS
  _clkmode = xtal1 + pll16x         ' enable external clock and pll times 16
  _xinfreq = 5_000_000              ' set frequency to 5 MHZ
  CLOCKS_PER_MICROSECOND = 5        ' simple xin / 1_000_000                     

  ' These settings are for 10 MHZ XTALS
  '_clkmode = xtal1 + pll8x          ' enable external clock and pll times 8
  '_xinfreq = 10_000_000             ' set frequency to 10 MHZ
  'CLOCKS_PER_MICROSECOND = 10       ' simple xin / 1_000_000                     

  _stack   = 128                    ' accomodate display memory and stack

  STATUS_LED             = 25 ' pin for status LED (try to PWM it!!!)
  
  ' Command supported by spi interface. In general the commands mimic a subset of the commands available for each
  ' associated driver, in other words, via the spi interface, we "expose" a subset of commands, so the client may
  ' use the driver(s). Of course, we only support a subset of the functionality as a starting point, you might want
  ' to add, subtract modify, etc. the code, but this is a good template to see how to interface to a number of different
  ' drivers so you can modify them, add new drivers and commands, etc.
  
  CMD_NULL               = 0

  ' graphics commands
  GFX_CMD_NULL           = 0

  ' NTSC commands
  GFX_CMD_NTSC_PRINTCHAR = 1
  GFX_CMD_NTSC_GETX      = 2
  GFX_CMD_NTSC_GETY      = 3
  GFX_CMD_NTSC_CLS       = 4
  
  ' VGA commands
  
  GFX_CMD_VGA_PRINTCHAR = 8
  GFX_CMD_VGA_GETX      = 9
  GFX_CMD_VGA_GETY      = 10
  GFX_CMD_VGA_CLS       = 11

  ' mouse and keyboard are "loadable" devices, user must load one or the other on boot before using it

  ' keyboard commands
{  KEY_CMD_RESET         = 16
  KEY_CMD_GOTKEY        = 17
  KEY_CMD_KEY           = 18
  KEY_CMD_KEYSTATE      = 19
  KEY_CMD_START         = 20
  KEY_CMD_STOP          = 21
  KEY_CMD_PRESENT       = 22
  
  ' mouse commands
  MOUSE_CMD_RESET       = 24 ' resets the mouse and initializes it
  MOUSE_CMD_ABS_X       = 25 ' returns the absolute X-position of mouse
  MOUSE_CMD_ABS_Y       = 26 ' returns the absolute Y-position of mouse
  MOUSE_CMD_ABS_Z       = 27 ' returns the absolute Z-position of mouse
  MOUSE_CMD_DELTA_X     = 28 ' returns the delta X since the last mouse call
  MOUSE_CMD_DELTA_Y     = 29 ' returns the delta Y since the last mouse call
  MOUSE_CMD_DELTA_Z     = 30 ' returns the delta Z since the last mouse call
  MOUSE_CMD_RESET_DELTA = 31 ' resets the mouse deltas
  MOUSE_CMD_BUTTONS     = 32 ' returns the mouse buttons encoded as a bit vector
  MOUSE_CMD_START       = 33 ' starts the mouse driver, loads a COG with it, etc.
  MOUSE_CMD_STOP        = 34 ' stops the mouse driver, unloads the COG its running on
  MOUSE_CMD_PRESENT     = 35 ' determines if mouse is present and returns type of mouse    
 }
 
  ' general data readback commands
  READ_CMD              = 36

  ' sound commands
  SND_CMD_PLAYSOUNDFM   = 40 ' plays a sound on a channel with the sent frequency at 90% volume
  SND_CMD_STOPSOUND     = 41 ' stops the sound of the sent channel 
  SND_CMD_STOPALLSOUNDS = 42 ' stops all channels
  SND_CMD_SETFREQ       = 43 ' sets the frequency of a playing sound channel        
  SND_CMD_SETVOLUME     = 44 ' sets the volume of the playing sound channel
  SND_CMD_RELEASESOUND  = 45 ' for sounds with infinite duration, releases the sound and it enters the "release" portion of ADSR envelope


  ' propeller local 8-bit port I/O commands
  PORT_CMD_SETDIR       = 48 ' sets the 8-bit I/O pin directions for the port 1=output, 0=input
  PORT_CMD_READ         = 49 ' reads the 8-bit port pins, outputs are don't cares
  PORT_CMD_WRITE        = 50 ' writes the 8-bit port pins, port pins set to input ignore data 

  ' general register access commands, Propeller registers for the SPI driver cog can be accessed ONLY
  ' but, the user can leverage the counters, and even the video hardware if he wishes, most users will only
  ' play with the counters and route outputs/inputs to/from the Propeller local port, but these generic access
  ' commands model how you would access a general register based system remotely, so good example
  ' these commands are DANGEROUS since you can break the COG with them and require a reset, so if you are going to
  ' write directly to the registers, be careful.

  REG_CMD_WRITE         = 56 ' performs a 32-bit write to the addressed register [0..F] from the output register buffer
  REG_CMD_READ          = 57 ' performs a 32-bit read from the addressed register [0..F] and stores in the input register buffer 
  REG_CMD_WRITE_BYTE    = 58 ' write byte 0..3 of output register g_reg_out_buffer.byte[  0..3  ]
  REG_CMD_READ_BYTE     = 59 ' read byte 0..3 of input register g_reg_in_buffer.byte[  0..3 ]

  ' system commands
  SYS_RESET             = 64 ' resets the prop

  ' ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  ' this range of commands for future expansion...
  ' ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  ' advanced GFX commands for GFX tile engine
  GPU_GFX_BASE_ID         = 192                  ' starting id for GFX commands to keep them away from normal command set
  GPU_GFX_NUM_COMMANDS    = 26                   ' number of GFX commands

  GPU_GFX_ONE_GAUGE       = (0+GPU_GFX_BASE_ID)
  GPU_GFX_TWO_GAUGE       = (1+GPU_GFX_BASE_ID)
  GPU_GFX_FOUR_GAUGE      = (2+GPU_GFX_BASE_ID)
  GPU_GFX_SIX_GAUGE_1     = (3+GPU_GFX_BASE_ID)
  GPU_GFX_SIX_GAUGE_2     = (4+GPU_GFX_BASE_ID)
  GPU_GFX_PARAM_LIST      = (5+GPU_GFX_BASE_ID)
  GPU_GFX_TIMERXY         = (6+GPU_GFX_BASE_ID)
  GPU_GFX_TIMER_SETXY     = (7+GPU_GFX_BASE_ID)
  GPU_GFX_CONFIG_SET      = (8+GPU_GFX_BASE_ID)
  GPU_GFX_PROCEDE_PGM     = (9+GPU_GFX_BASE_ID)
  GPU_GFX_FIRMWARE_PGM    = (10+GPU_GFX_BASE_ID)
  GPU_GFX_DATA_LOG        = (11+GPU_GFX_BASE_ID)
  GPU_GFX_CAN_SNIFFER     = (12+GPU_GFX_BASE_ID)
  GPU_GFX_V1              = (13+GPU_GFX_BASE_ID)
  GPU_GFX_REFRESH_ACTIVE  = (14+GPU_GFX_BASE_ID)
  GPU_GFX_TERMINAL_PRINT  = (15+GPU_GFX_BASE_ID)
  GPU_GFX_BOTTOM_MENU     = (16+GPU_GFX_BASE_ID)
  GPU_GFX_HIGHLIGHT       = (17+GPU_GFX_BASE_ID)
  GPU_GFX_CLS_MAIN        = (18+GPU_GFX_BASE_ID)
  GPU_GFX_SPLASH_IN       = (19+GPU_GFX_BASE_ID)
  GPU_GFX_SPLASH_OUT      = (20+GPU_GFX_BASE_ID)
  GPU_GFX_DRAW_BOX        = (21+GPU_GFX_BASE_ID)
  GPU_GFX_PRINT_XY        = (22+GPU_GFX_BASE_ID)
  GPU_GFX_PRINT_SETXY     = (23+GPU_GFX_BASE_ID)
  GPU_GFX_TIMERFATS       = (24+GPU_GFX_BASE_ID)
  GPU_GFX_TIMER_SETFATS   = (25+GPU_GFX_BASE_ID)

  ONE_GAUGE       = 10
  TWO_GAUGE       = 11
  FOUR_GAUGE      = 12
  SIX_GAUGE       = 13
  PARAM_LIST      = 14
  TIMER_XY        = 15
  TIMER_FATS      = 16
  CONFIG_SET      = 17
  PROCEDE_FW_PGM  = 18
  PROCEDE_MAP_PGM = 19
  CAN_SNIFFER     = 20
  IDRIVINO_RESET  = 21
  DATA_LOG        = 22
  VALENTINE1      = 23

  MENU_BAR        = 30  
  
'//////////////////////////////////////////////////////////////////////////////
' VARS SECTION ////////////////////////////////////////////////////////////////
'//////////////////////////////////////////////////////////////////////////////        
  
VAR

  long g_spi_cmdpacket                              ' command packet
  byte g_cmd, g_data, g_data2, g_status             ' command packet bytes
  long g_data16, g_spi_result
  long g_snd_chan, g_snd_freq, g_snd_dur, g_snd_vol ' some sound globals

  ' these a buffers for 4-byte operations, since the SPI interface is a byte device more or less,
  ' we need a strategy to build up 32-bit operands and retrieve 32-bit data, so these buffers are
  ' for that purpose and specifically to support the COG register access commands
  long g_reg_in_buffer[1], g_reg_out_buffer[1]

  long active_screen
  long lastparam,four1_2,lastspeed
  byte box_last,x,y 

'//////////////////////////////////////////////////////////////////////////////
'OBJS SECTION /////////////////////////////////////////////////////////////////
'//////////////////////////////////////////////////////////////////////////////

OBJ

' current drivers used in this version of SPI interface 
'term_ntsc  : "TV_Text_Half_Height_011.spin"        ' instantiate NTSC terminal driver

spi        : "SPI_CMD_drv_010.spin"                ' instantiate spi command driver
'term_vga   : "VGA_Text_010.spin"                   ' instantiate VGA terminal driver
'kbd        : "keyboard_010.spin"                   ' instantiate keyboard driver
'mouse      : "mouse_010.spin"                      ' instantiate mouse driver 
'snd        : "NS_sound_drv_052_11khz_16bit.spin"   ' instantiate sound driver         
gfx_ntsc   : "GraphicsPaletteHelper.spin"        ' instantiate new NTSC tile driver


'//////////////////////////////////////////////////////////////////////////////
'PUBS SECTION /////////////////////////////////////////////////////////////////
'//////////////////////////////////////////////////////////////////////////////

PUB Main : status

  ' let the system initialize 
  Delay( 1*1_000_000 )

  ' initialize VGA terminal
  'term_vga.start(%10111)   

  ' delay a moment
  'Delay(1*10_000)

  'print a string VGA
  'term_vga.pstring(@spi_startup_string)
  'term_vga.newline
  'term_vga.pstring(@ntsc_startup_string)
  'term_vga.pstring(@vga_startup_string)  

  ' initialize the graphics tile engine
  gfx_ntsc.start

  ' delay a moment
  Delay(1*10_000)

  'gfx_ntsc.String_Term(@spi_startup_string)
  'gfx_ntsc.Newline_Term
  'gfx_ntsc.String_Term(@ntsc_startup_string)
  'gfx_ntsc.String_Term(@vga_startup_string)  

  ' start sound engine up
  'snd.start(24)

  ' delay a moment
  'Delay(1*10_000)

  'term_vga.pstring(@sound_startup_string)
  'gfx_ntsc.String_Term(@sound_startup_string)

  ' start the SPI virtual peripheral
  status := spi.start

  ' delay a moment
  Delay(1*10_000)

  ' make a little noise
  'snd.PlaySoundFM(0, snd#SHAPE_SQUARE, snd#NOTE_C4, CONSTANT( Round(Float(snd#SAMPLE_RATE) * 0.25)), 200, $3579_ADEF )
  'repeat 50_000
  'snd.PlaySoundFM(1, snd#SHAPE_SQUARE, snd#NOTE_C5, CONSTANT( Round(Float(snd#SAMPLE_RATE) * 0.25)), 200, $3579_ADEF )
  'repeat 50_000
  'snd.PlaySoundFM(2, snd#SHAPE_SQUARE, snd#NOTE_C6, CONSTANT( Round(Float(snd#SAMPLE_RATE) * 0.25)), 200, $3579_ADEF )

  'start keyboard on chameleon pins, keyboard is always started even if its not plugged in
  'kbd.start(26, 27)

  ' delay a moment
  'Delay(1*10_000)

  'term_vga.pstring(@keyboard_startup_string)

  'gfx_ntsc.String_Term(@keyboard_startup_string)

  'gfx_ntsc.Newline_Term
  'gfx_ntsc.String_Term(@spi_ready_string)

  'term_vga.newline
  'term_vga.pstring(@spi_ready_string)

  ' blink the status LED 3 times to show board is "alive"
  DIRA[25] := 1 ' set to output
  OUTA[25] := 0

  ' initalize any variables for the first time
  active_screen := 0
  lastparam := 0
  lastspeed := 0  

  repeat 6
    OUTA[25] := !OUTA[25]
    repeat 25_000 
 
  ' ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  ' MAIN LOOP - Listen for packets to finish then execute commands sent to Prop over SPI interface
  ' the longer this loop is the slower processing will be, thus you will want to remove unecessary driver support for
  ' your custome drivers and of course port to ASM and blend this with the virtual SPI driver code as well for the
  ' best performance.
  ' ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////  
  repeat

    ' wait for SPI driver to receive a command packet in shared memory
    g_spi_cmdpacket := spi.getcmd

    ' extract cmd 8-bit, data 8-bit, status 8-bit
    g_cmd   := ((g_spi_cmdpacket >> 16) & $FF) 
    g_data  := ((g_spi_cmdpacket >> 8)  & $FF)              ' low byte of 16-bit data
    g_data2 := g_status := ((g_spi_cmdpacket >> 0)  & $FF)  ' high byte of 16-bit data

    ' build 16-bit data (may not be valid though based on command)
    g_data16 := (g_data2<< 8) | (g_data)

    ' now process command to determine what user is client is requested via spi link
      case ( g_cmd )


        GFX_CMD_NULL:

        ' GFX GPU TILE ENGINE COMMANDS /////////////////////////////////////////////////////////////////////////////////////////

         'catch all commands right here
        'GPU_GFX_BASE_ID..(GPU_GFX_BASE_ID + GPU_GFX_NUM_COMMANDS - 1):

          ' call single processing function...
          'g_spi_result := gfx_ntsc.GPU_GFX_Process_Command( g_cmd, g_data16 )

        GPU_GFX_TERMINAL_PRINT:
          g_spi_result := gfx_ntsc.TerminalPrint(g_data)

        ' // NTSC GFX/TILE SPECIFIC COMMANDS ///////////////////////////////////////////////////////////////////////////////////
        ' we only expose a subset of the commands the driver supports, you can add/subtract more commands as desired
        ' some commands like PRINTCHAR for example internally support a number of sub-commands that we don't need to expose
        ' at this level unless we want to add funcitonality        
        GFX_CMD_NTSC_PRINTCHAR:
          ' this command pipes right to the out() function of the driver which supports the following sub-commands already
          '
          '     $00 = clear screen
          '     $01 = home
          '     $08 = backspace
          '     $09 = tab (8 spaces per)
          '     $0A = set X position (X follows)
          '     $0B = set Y position (Y follows)
          '     $0C = set color (color follows)
          '     $0D = return
          '  anything else, prints the character to terminal
          
          'gfx_ntsc.Out_Term( g_data )
           
        GFX_CMD_NTSC_GETX:
          ' return x position in spi buffer, next read will pull it out on last byte of 3-byte packet
          'g_spi_result := gfx_ntsc.GetX

        GFX_CMD_NTSC_GETY:
          ' return y position in spi buffer, next read will pull it out on last byte of 3-byte packet
          'g_spi_result := gfx_ntsc.GetY

        GFX_CMD_NTSC_CLS: ' eventhough this command is supported above,we break it out as a seperate SPI command just in case we want to
                          ' add functionality on top of, like "overloading" and handling manually, notice we end up calling the $00 sub-command
                          ' but we have the flexibility to add stuff if we desire...
          'gfx_ntsc.Out_Term( $00 )
          ' add other functionality to the clear screen here...
          gfx_ntsc.ClearScreen

        GPU_GFX_CLS_MAIN:
          ' clears the "main" window (everything except the bottom menu)
          gfx_ntsc.ClearMainWindow

        GPU_GFX_ONE_GAUGE:
          active_screen := ONE_GAUGE
          if (g_data == $9D)
            'set up to load upcoming parameter in next SPI cmd
            lastparam := g_data2  'g_data2 = gauge position
          elseif (g_data2 == $9D)
            'draw initial display            
            g_spi_result := gfx_ntsc.DrawOneGauge(g_data) 'g_data = gaugetype
          else
            ~~g_data16
            g_spi_result := gfx_ntsc.UpdateGauge(1,lastparam,g_data16)            

        GPU_GFX_TWO_GAUGE:
          active_screen := TWO_GAUGE
          if (g_data == $9D)
            'set up to load upcoming parameter in next SPI cmd
            lastparam := g_data2
          elseif (g_data2 == $9D)
            'draw initial display
            g_spi_result := gfx_ntsc.DrawTwoGauge(g_data)
          else
            ~~g_data16
            'update 1 parameter at a time in display
            g_spi_result := gfx_ntsc.UpdateGauge(2,lastparam,g_data16)
          
        GPU_GFX_FOUR_GAUGE:
          active_screen := FOUR_GAUGE
          if (g_data == $9D)
            'set up to load upcoming parameter in next SPI cmd
            lastparam := g_data2
          elseif (g_data2 == $9D)
            'draw initial display
            four1_2 := g_data
          elseif (g_data2 == $9E)
            g_spi_result := gfx_ntsc.DrawFourGauge(four1_2,g_data)
          else
            ~~g_data16
            'update 1 parameter at a time in display
            g_spi_result := gfx_ntsc.UpdateGauge(4,lastparam,g_data16)

        {GPU_GFX_SIX_GAUGE_1:
          active_screen := SIX_GAUGE
          g_spi_result := gfx_ntsc.SixGauge1(g_data,g_data2)

        GPU_GFX_SIX_GAUGE_2:
          active_screen := SIX_GAUGE
          g_spi_result := gfx_ntsc.SixGauge2(g_data)}

        GPU_GFX_PARAM_LIST:
          active_screen := PARAM_LIST
          'Check for 0x9D (-99), cannot use -99 because byte is unsigned in SPIN
          if (g_data == $9D)
            'set up to load upcoming parameter in next SPI cmd
            lastparam := g_data2
          elseif ((g_data == 0) and (g_data2 == $9D))
            'draw initial Param List display 
            g_spi_result := gfx_ntsc.ParamList(g_data,g_data2)
          else
            'Check for 16-bit negative number & convert to 32-bit long
            ~~g_data16
            'update 1 parameter at a time in Param List display   
            g_spi_result := gfx_ntsc.ParamList(g_data16,lastparam)

        GPU_GFX_TIMERXY:
          active_screen := TIMER_XY

          if (g_data == $9D)
            lastparam := g_data2
          else
            ~~g_data16
            'g_spi_result := gfx_ntsc.TimerXYUpdate(lastspeed,g_data16)
            g_spi_result := gfx_ntsc.UpdateGauge(2,lastparam,g_data16)

        GPU_GFX_TIMER_SETXY:
          active_screen := TIMER_XY
          g_spi_result := gfx_ntsc.TimerSetXY(g_data,g_data2)

{        GPU_GFX_CONFIG_SET:
          active_screen := CONFIG_SET
          g_spi_result := gfx_ntsc.ConfigSet

        GPU_GFX_PROCEDE_PGM:
          active_screen := PROCEDE_PGM
          g_spi_result := gfx_ntsc.ProcedeProgram

        GPU_GFX_FIRMWARE_PGM:
          active_screen := IDRIVINO_PGM
          g_spi_result := gfx_ntsc.FirmwareProgram

        GPU_GFX_DATA_LOG:
          active_screen := DATA_LOG
          g_spi_result := gfx_ntsc.DataLog

        GPU_GFX_CAN_SNIFFER:
          active_screen := CAN_SNIFFER
          g_spi_result := gfx_ntsc.TerminalPrint2Column(g_data)

        GPU_GFX_V1:
          active_screen := VALENTINE1
          g_spi_result := gfx_ntsc.V1
}

        'GPU_GFX_REFRESH_ACTIVE:
        '  g_spi_result := gfx_ntsc.RefreshActive(g_data,g_data2)
          
        GPU_GFX_BOTTOM_MENU:
          if (g_data2 == $9D)
            'update highlight tab            
            g_spi_result := gfx_ntsc.DrawBottomMenu(g_data)
          elseif (g_data == $FF)
            'update map #
            g_spi_result := gfx_ntsc.UpdateBottomMenuMap(g_data2)
          else
            ~~g_data16 'g_data16 = at boost lvl
            g_spi_result := gfx_ntsc.UpdateBottomMenuBoost(g_data16)

        GPU_GFX_HIGHLIGHT:
          'Highlight item of interest
          if (g_data2 == $9D)
            g_spi_result := gfx_ntsc.HighlightMenuWindow(g_data)
          else             
            g_spi_result := gfx_ntsc.HighlightMainWindow(g_data,g_data2)

        GPU_GFX_SPLASH_IN:
          'g_spi_result := gfx_ntsc.DrawIntroSplash(g_data)

        GPU_GFX_SPLASH_OUT:
          g_spi_result := gfx_ntsc.DrawOutroSplash(g_data)

        GPU_GFX_DRAW_BOX:
          if (box_last == 0)
            x := g_data
            y := g_data2
            box_last := 1
          else
            g_spi_result := gfx_ntsc.DrawBox(x,y,g_data,g_data2)
            box_last := 0

        GPU_GFX_PRINT_SETXY:
          g_spi_result := gfx_ntsc.Print_SetXY(g_data,g_data2)

        GPU_GFX_PRINT_XY:
          g_spi_result := gfx_ntsc.Print_WriteXY(g_data,g_data2)

       {   
        ' // PS/2 KEYBOARD SPECIFIC COMMANDS /////////////////////////////////////////////////////////////////////////
        ' we only expose a subset of the commands the driver supports, you can add/subtract more commands as desired
        
        KEY_CMD_RESET:
          kbd.clearkeys

        ' these are "read" class commands, so what we need to do is push the data into the spi buffer,
        ' then when the user reads the next byte of data with a spi transmission, the data will be available
        ' the lack of integration with the spi peripheral and the SPIN command processor are klunky for testing
        ' later this would be cleaned up in real driver code, thus the trick is to allow the user to send the first
        ' entire payload [command, data, status] THEN we push the result into the spi buffer and the user performs a
        ' READ_CMD this gets the data and we are good to go!           

        KEY_CMD_GOTKEY:
          if (kbd.gotkey == TRUE)
            g_spi_result := 1
          else
            g_spi_result := 0
           
        KEY_CMD_KEY:
          g_spi_result := kbd.key
                
        KEY_CMD_KEYSTATE:
          g_spi_result := kbd.keystate( g_data )
          'term_ntsc.out( kbd.key )

        ' these commands are for starting and stopping the keyboard object. when the driver starts it assumes the keyboard is plugged in.
        ' its up to the user to stop the keyboard driver and then do nothing or to load the mouse driver if he wants to use mouse.
        ' the "present" commands can be used to determine if the keyboard or mouse is plugged in, but to use them the user must make sure to
        ' start the keyboard or mouse. 
        
        KEY_CMD_START:
          kbd.stop
          kbd.start(26, 27)
                
        KEY_CMD_STOP:

          'mouse.stop
          repeat 100 ' wait a sec for things to settle
        
          kbd.stop
           
        KEY_CMD_PRESENT:
          g_spi_result := kbd.present
          
        ' // PS/2 SPECIFIC COMMANDS////////////////////////////////////////////////////////////////////////////////////////
        ' mouse commands, we only expose a sub-set of the commands here, you can add more, remove some, etc.

    
        MOUSE_CMD_RESET:
          ' do reset chores here, mouse driver has no reset, so nothing to pass along

        MOUSE_CMD_ABS_X:
          g_spi_result := mouse.abs_x 

'         
        MOUSE_CMD_ABS_Y:
          g_spi_result := mouse.abs_y

'         
        MOUSE_CMD_ABS_Z:
          g_spi_result := mouse.abs_z

 '        
        MOUSE_CMD_DELTA_X:
          g_spi_result :=  mouse.delta_x
'         
        MOUSE_CMD_DELTA_Y:
          g_spi_result := mouse.delta_y
'         
        MOUSE_CMD_DELTA_Z:
          g_spi_result := mouse.delta_z
'         
        MOUSE_CMD_RESET_DELTA:
          g_spi_result := mouse.delta_reset

        MOUSE_CMD_BUTTONS:
          '' Get the states of all buttons
          '' returns buttons:
          ''
          ''   bit4 = right-side button
          ''   bit3 = left-side button
          ''   bit2 = center/scrollwheel button
          ''   bit1 = right button
          ''   bit0 = left button
          g_spi_result := mouse.buttons
          
         
        MOUSE_CMD_START:
          ' start mouse on chameleon pins, mouse is only started by request of user. Also, since keyboard is always started even if its not plugged in
          ' we try to stop the keyboard, so we don't use another COG needlesly
                    
          kbd.stop
          repeat 100 ' wait a sec for things to settle

          ' now start up mouse (hope one is plugged in!)
          mouse.stop
          mouse.start(26, 27)

        MOUSE_CMD_STOP:
          mouse.stop


        MOUSE_CMD_PRESENT: 

        '' Check if mouse present - valid ~2s after start
        '' returns mouse type:
        ''
        ''   3 = five-button scrollwheel mouse
        ''   2 = three-button scrollwheel mouse
        ''   1 = two-button or three-button mouse
        ''   0 = no mouse connected
        
          g_spi_result := mouse.present
          

        ' // READ SPECIFIC COMMANDS ///////////////////////////////////////////////////////////////////////////////////
        READ_CMD:
          ' do nothing, the result was placed in the previous command, thus this dummy command is used to transport
          ' the results back to the host
          ' reset result, by the time this command is complete its been sent back
          ' g_spi_result := 1000   
        

        ' // SOUND SPECIFIC COMMANDS ///////////////////////////////////////////////////////////////////////////////////
        ' we only expose a subset of the commands the driver supports, you can add/subtract more commands as desired
                
        SND_CMD_PLAYSOUNDFM:  ' plays a sound on a channel with the sent frequency at 90% volume
          ' data8[cc.ddd.fff ] | data8[ ffffffff ]
          ' channel 2-bit (0..3) | duration 3-bit 0..7 | frequency 11-bit (0 turn off channel)
          g_snd_chan := (g_data2 >> 6) & %000000_11
          g_snd_dur  := (g_data2 >> 3) & %00000_111
          g_snd_freq := (g_data16 & %00000_111_11111111)

          ' check for out of range
          if (g_snd_freq > 0)
            snd.PlaySoundFM(g_snd_chan, snd#SHAPE_SINE, g_snd_freq, snd#SAMPLE_RATE * g_snd_dur, 200, $3579_ADEF )
          else
            snd.StopSound( g_snd_chan )
           
        SND_CMD_STOPSOUND:    ' stops the sound of the sent channel 
          snd.StopSound( g_snd_chan )

        SND_CMD_STOPALLSOUNDS: ' stops all channels
          repeat g_snd_chan from 0 to 3
            snd.StopSound( g_snd_chan )

        SND_CMD_SETFREQ:       ' sets the frequency of a playing sound channel
          ' data8[cc.xxx.fff ] | data8[ ffffffff ]
          ' channel 2-bit (0..3) | dummy 3-bit xxx| frequency 11-bit (0 turn off channel)
          g_snd_chan := (g_data >> 6) & %000000_11
          g_snd_freq := (g_data16 & %00000_111_11111111)

          ' update frequency
          snd.SetFreq(g_snd_chan, g_snd_freq)          

        SND_CMD_SETVOLUME:     ' sets the volume of the playing sound channel
          ' data8[cc.xxxxxx ] | data8[ ffffffff ]
          ' channel 2-bit (0..3) | dummy 6-bit xxxxxx| volume 8-bit (1..255, 0 leave volume same)
          g_snd_chan := (g_data >> 6) & %000000_11
          g_snd_vol  := (g_data16 & %00000000_11111111)

          ' update volume
          snd.SetVolume(g_snd_chan, g_snd_vol)           

        SND_CMD_RELEASESOUND:  ' for sounds with infinite duration, releases the sound and it enters the "release" portion of ADSR envelope
          ' data8[cc.xxxxxx ] | data8[ xxxxxxxx ]
          ' channel 2-bit (0..3) | dummy 6-bit xxxxxx | dummy 8-bit xxxxxxxx
          g_snd_chan := (g_data >> 6) & %000000_11

          ' release the infinite sound
          snd.ReleaseSound(g_snd_chan)   
        }

        ' // Propeller local port specific commands ///////////////////////////////////////////////////////////////////
        ' these are handled locally in SPIN on the interface driver's COG

        PORT_CMD_SETDIR:      ' sets the 8-bit I/O pin directions for the port 1=output, 0=input
          DIRA[7..0] := g_data      

        PORT_CMD_READ:        ' reads the 8-bit port pins, outputs are don't cares
          g_spi_result := (INA[7..0] & $FF) ' data is now in g_spi_result, client must perform a general READ_CMD to get it back        

        PORT_CMD_WRITE:       ' writes the 8-bit port pins, port pins set to input ignore data 
          OUTA[7..0] := g_data


        ' // Propeller SPI driver register access commands /////////////////////////////////////////////////////////////
        ' these are handled locally in SPIN on the interface driver's COG, thus all register access is on the COG running
        ' the spin interpreter for the driver, should be COG 0

        ' final write/read commands, these two commands are used to do the actual work of reading and writing to the COG
        ' registers -- HOWEVER, to get the "data" in and out, the byte read/write commands are used
        
        REG_CMD_WRITE:       ' performs a 32-bit write to the addressed register [0..F] from the output register buffer
          SPR [ g_data ] := g_reg_out_buffer
        
        REG_CMD_READ:        ' performs a 32-bit read from the addressed register [0..F] and stores in the input register buffer 
          g_reg_in_buffer := SPR [ g_data ]
           
        ' write command to byte registers of 32-bit buffer register
                 
        REG_CMD_WRITE_BYTE:  ' write byte 0..3 of output register g_reg_out_buffer.byte[  0..3  ]
          ' byte address to write 0..3 is in g_data while data to write is in g_data2
          g_reg_out_buffer.byte[ g_data ] := g_data2

        ' read command from byte registers of 32-bit buffer register
                 
        REG_CMD_READ_BYTE:   ' read byte 0..3 of input register g_reg_in_buffer.byte[  0..3 ]
                             ' this data is then placed into spi buffer for transport back to client
          ' byte address to read 0..3 is in g_data
          g_spi_result := g_reg_in_buffer.byte[ g_data ] 


        SYS_RESET:     ' resets the prop
          reboot

      ' end case commands

    ' set result and set dispatcher to idle
    spi.finishcmd(g_spi_result)

    ' // end main loop
    ' ////////////////////////////////////////////////////////////////////////  

'//////////////////////////////////////////////////////////////////////////////

PUB Delay( time_us )
  
  waitcnt ( CNT + time_us * CLOCKS_PER_MICROSECOND ) 

'//////////////////////////////////////////////////////////////////////////////

PUB Stop

  spi.stop

'//////////////////////////////////////////////////////////////////////////////
{DAT

spi_startup_string  byte      " Chameleon SPI Driver2 V1.12", $0D, $00
spi_ready_string    byte      " Ready for commands...", $0D, $00
spi_data_string     byte      "SPI data = ", $00

sound_startup_string    byte  " Sound Driver Initialized.", $0D, $00
keyboard_startup_string byte  " Keyboard Driver Initialized.", $0D, $00
ntsc_startup_string     byte  " NTSC Driver Initialized.", $0D, $00
vga_startup_string      byte  " VGA Driver Initialized.", $0D, $00

newline_string      byte      $0D, $0A, $00  ' $0D carriage return, $0A line feed
}