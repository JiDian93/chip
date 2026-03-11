// This special monitor file monitors signals in the system.sv module


//--------------------------------
//  Time
//--------------------------------

initial
  $timeformat(0,2, " s", 10 );

// print the time once a second
//
always #1s
  $display("%t",$time );

//--------------------------------
//  Mode
//--------------------------------

initial
  $monitor("           Mode %0d", mode_index );

//--------------------------------
//  Environmental Conditions
//--------------------------------

// watch for changes in wind direction
//
always
  begin
    // note that "%n" is used here to print the enumerated variable
    // rather than the number that it represents
    //
    $display("           Wind Direction %n", VANE.WindDirection );
    @(VANE.WindDirection);
  end

// watch for changes in atmospheric pressure
//
always
  begin
    $display("           Pressure %0.2f mb", SENSOR.pressure );
    @(SENSOR.pressure);
  end

// watch for changes in temperature
//
always
  begin
    $display("           Temperature %0.1f C", SENSOR.temperature );
    @(SENSOR.temperature);
  end

// Note that only one $monitor command can be active at any one time.
// Using separate always blocks to monitor the environmental
// conditions avoids the information overload that might be seen with
// all values being observed via a single $monitor command.
