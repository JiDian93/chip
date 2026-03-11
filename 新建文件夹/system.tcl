
# system.tcl

simvision {

  # Open new waveform window
  
    window new WaveWindow -name "Waves for Example Weather Station Design"
    waveform using "Waves for Example Weather Station Design"

  # add Clock and nReset to wave window
  
    waveform  add -signals  system.Clock
    waveform  add -signals  system.nReset

  # add signals which represent the weather being observed

    waveform  add -signals  system.nRain
    waveform  add -signals  system.nWind
    waveform  add -signals  system.VANE.WindDirection

  # add pressure to wave window as sampled analogue signal
  
    set id [ waveform  add -signals  system.SENSOR.pressure ]
    waveform format $id -trace analogSampleAndHold
    waveform axis range $id -min 980 -max 1030 -scale linear

    set id [ waveform  add -signals  system.SENSOR.temperature ]
    waveform format $id -trace analogSampleAndHold
    waveform axis range $id -min 0 -max 30 -scale linear


  # add remaining weather station I/O to wave window
  
    waveform  add -signals  system.nMode
    waveform  add -signals  system.nStart
    waveform  add -signals  system.nVaneCS
    waveform  add -signals  system.nBaroCS
    waveform  add -signals  system.SPICLK
    waveform  add -signals  system.MOSI
    waveform  add -signals  system.MISO
    waveform  add -signals  system.RS
    waveform  add -signals  system.RnW
    waveform  add -signals  system.En
    waveform  add -signals  system.DB
    waveform  add -signals  system.mode_index

    
}

# =========================================================================
# Probe

  # Any signals included in register window but not in waveform window
  # should be probed
  
# =========================================================================
