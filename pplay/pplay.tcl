package require Tk

namespace eval MPClient {

set chan {}
set mp_host localhost
set mp_port 6600
set requested_random 1
array set widget {}
array set status {
}

array set currentsong {}
array set evdata {}
array set playlistinfo {}
set playlist {}
set ping_id {}

proc mp_event { evname data } {
	variable evdata
	puts "EV : $evname"
	if { [ bind . $evname ] == {} } {
		bind . $evname "[namespace current]::Dispath %W $evname ; continue"
		update idletasks
	}
	catch {
		if { [ bind .mp $evname ] == {} } {
			bind .mp $evname "[namespace current]::Dispath %W $evname ; continue"
			update idletasks
		}
	}
	set evdata($evname) $data
	after 100 event generate . $evname	
}

proc disconnect {} {
	variable chan
	catch { close $chan }
	set chan {}
	puts "disconnected"
}

proc reconnect {} {
	variable mp_port 
	variable mp_host
	disconnect
	after 100
	connect $mp_host $mp_port 
}

proc connect { {host localhost} {port 6600} } {
	variable chan
	variable mp_port 
	variable mp_host
	set mp_port $port
	set mp_host $host
	if { $chan != {} } {
		disconnect
	}
	set chan [ socket $host $port ]
	fconfigure $chan -encoding utf-8
	set str [ gets $chan ]
	puts "SERVER STRING : $str"
	set ok [ lindex $str 0 ]
	if { $ok != "OK" } {
		disconnect
	}
	if { $chan != {} } {
		puts "connected"
	}
	set ping_id [ after 3000 [namespace current]::periodic_ping 6000 ]
	status
	currentsong
}

proc periodic_ping { delay } {
	variable ping_id
	variable status
	puts "{TICK}"
	status
	currentsong
	set ping_id [ after $delay [namespace current]::periodic_ping $delay ]
}

proc Dispath { w evname } {
	flush stdout
	foreach child [ winfo children $w ] {
		puts "$evname->$child"
		event generate $child $evname -when tail
	}
}

proc status {} {
	variable chan
	variable status
	if { $chan == {} && ! [ reconnect ] } {
		set status(state) "not connected"
		return 0
	}
	array set newstatus {}
	foreach line [ mp_send "status" ] {
		if [ regexp {^([a-zA-Z ]+):(.*)$} [ string trim $line ] all key value ] {
			set key [ string trim $key ]
			set value [ string trim $value ]
			if { ! [ info exists status($key) ] } {
				set status($key) {}
			}
			if { $status($key) != $value } {
				set evname <<mp-status-$key>>
				mp_event $evname $value
				puts "generated <<mp-status-$key>>"
			}
			set newstatus($key) $value
		}
	}
	array set status [ array get newstatus ]
	return 1
}

proc currentsong {} {
	variable currentsong
	array set newsong {}
	puts "{currentsong}"
	foreach line [ mp_send "currentsong" ] {
		if [ regexp {^([a-zA-Z ]+):(.*)$} [ string trim $line ] all key value ] {
			set key [ string trim $key ]
			set value [ string trim $value ]
			if { ! [ info exists currentsong($key) ] } {
				set currentsong($key) {}
			}
			if { $currentsong($key) != $value } {
				mp_event [ string tolower "<<mp-currentsong-$key>>" ] $value
				puts "generated <<mp-currentsong-$key>>"
			} else {
				puts "NO CHG"
			}
			set newsong($key) $value
		} else {
			puts "NO PARSE : $line"
		}
	}
	array set currentsong [ array get newsong ]
	return 1
}

proc play {} {
	mp_send "play"
	status
	currentsong
}

proc stop {} {
	mp_send "stop"
	status
}

proc add {} {
	mp_send "add"
}

proc pause {} {
	mp_send "pause"
	status
}

proc shuffle {} {
	mp_send "shuffle"
}

proc playlist {} {
	mp_send "playlist"
}

proc random { {flag {} } } {
	variable status
	if { $flag == {} } {
		set flag [ expr ! $status(random) ]
	}
	mp_send "random $flag"
}

proc playlistinfo {} {
	variable playlist
	variable playlistinfo
	set playlist {}
	array unset playlistinfo
	array set playlistinfo {}
	foreach line [ mp_send "playlistinfo" ] {
		if [ regexp {^([a-zA-Z ]+):(.*)$} $line all key value ] {
			set key [ string trim $key ]
			set value [ string trim $value ]
			set tmp($key) $value
			if { $key == "Id" } {
				foreach subkey [ array names tmp ] {
					set playlistinfo($value,$subkey) $tmp($subkey)
				}
				lappend playlist $value
				array unset tmp
			}
		}
	}
}

proc mp_send { cmd } {
	variable chan
	variable widget
	if { $chan == {} } {
		return
	}
	puts $chan $cmd
	flush $chan
	set ls {}
	puts "> $cmd"
	while { ! [ eof $chan ] } {
		if [ catch {
			set str [ string trim [ gets $chan ] ]
		} ] {
			puts "BAD : $str"
			continue
		}
		if { $str == {} } {
			if [ eof $chan ] {
				disconnect
				return
			}
			puts ".."
			continue
		}
		lappend ls $str
		if { $str == "OK" } {
			puts "RET : $ls"
			return $ls
		}
		if [ string match "ACK *" $str ] {
			puts "FAULT COMMAND"
			return {}
		}
	}
	puts "RET : $ls"
	return $ls
}

proc next {} {
	mp_send "next"
	status
	currentsong
}

proc prev {} {
	mp_send "previous"
	status
	currentsong
}

proc repeat { flag } {
	mp_send "repeat $flag"
	status
}

proc crossfade { value } {
	mp_send "crossfade $value"
	status
}

proc seek { songId pos } {
	puts "DO SEEK"
	mp_send "seek $songId $pos"
	status
	currentsong
}

proc GUI_volume { value } {
	variable status
	variable widget
	mp_send "setvol $value"
	status
}

proc song_timer {} {
	variable status 
	variable widget
	if { $status(state) == "play" && 
		[ info exists widget(songScale) ] && 
		[ winfo exists $widget(songScale) ] } {
		set clk [ $widget(songScale) get ]
		$widget(songScale) set [ expr $clk + 1 ]
	}
#	after 1000 [namespace current]::song_timer
}

proc GUI_volume_timed { value } {
	variable volume_id
	if { [ info exists volume_id ] && $volume_id != {} } {
		after cancel $volume_id
	}
	set volume_id [ after 100 [namespace current]::GUI_volume $value ]
}

proc ChangeRedirect { w } {
	variable allow_update
	set allow_update 0
	set top [ winfo toplevel $w ]
	set redirect [ expr ! [ wm overrideredirect $top ] ]
	wm withdraw $top
	puts "------ $redirect -------"
	wm overrideredirect $top $redirect
	update
	after 100
	update
	wm deiconify $top
	puts "+++REDIR++"
	set allow_update 1
	update
}

proc StartDrag { w X Y } {
	variable mousex
	variable mousey
	set mousex $X
	set mousey $Y
}

proc Drag { w X Y b } {
	variable mousex
	variable mousey
	set top [ winfo toplevel $w ]
	set redirect [ wm overrideredirect $top ]
	if { ! $redirect } {
		return
	}
	set dx [ expr $X - $mousex ]
	set dy [ expr $Y - $mousey ]
	puts "dx=$dx dy=$dy"
	set x [ expr [ winfo rootx $top ] + $dx ]
	set y [ expr [ winfo rooty $top ] + $dy ]
	if { [ expr $x + [ winfo width $top ] > [ winfo screenwidth $top ] ] } {
		set x [ expr [ winfo screenwidth $top ] - [ winfo width $top ] ]
	}
	if { [ expr $x < 0 ] } {
		set x 0
	}
	if { [ expr $y + [ winfo height $top ] > [ winfo screenheight $top ] ] } {
		set y [ expr [ winfo screenheight $top ] - [ winfo height $top ] ]
	}
	if { [ expr $y < 0 ] } {
		set y 0
	}
	wm geometry $top +$x+$y
	puts "geometry $top +$x+$y"
	set mousex $X
	set mousey $Y
}

proc GUI_stop_button { w } {
	button $w -text "Stop" -command [ namespace code stop ]
		bind $w <<mp-status-state>> [ namespace code {
			puts "evdata = $evdata(<<mp-status-state>>)"
			switch -- $evdata(<<mp-status-state>>) {
				"play" -
				"pause" {
					$widget(stop) configure -state normal
				} default {
					$widget(stop) configure -state disabled
				}
			}
		} ]
	return $w
}

proc GUI_play_button_cmd { w } {
	variable status
	switch -- $status(state) {
		"play" {
			stop
		} "pause" {
			pause
		} default {
			puts "******** state=$status(state)"
			play
		}
	}
}

proc GUI_play_button { w } {
	button $w -text "Play" -command [ list [namespace current]::GUI_play_button_cmd $w ]
	bind $w <<mp-status-state>> [ namespace code {
		switch -- $evdata(<<mp-status-state>>) {
			"pause" -
			"play" {
				puts "sunken PLAY"
				$widget(play) configure -relief sunken
			} 
			"stop" {
				puts "raised PLAY"
				$widget(play) configure -relief raised
			}
		}
	} ]
	return $w
}

proc GUI_pause_button_cmd { w } {
	variable status 
	pause
}

proc GUI_pause_button { w } {
	button $w -text "Pause" -command [ list [namespace current]::GUI_pause_button_cmd $w ]
	bind $w <<mp-status-state>> [ namespace code {
		switch -- $evdata(<<mp-status-state>>) {
			"play" {
				$widget(pause) configure -relief raised -state normal
			} 
			"pause" {
				$widget(pause) configure -relief sunken -state normal
			}
			"stop" {
				$widget(pause) configure -relief raised -state disabled
			}
		}
	} ]
	return $w
}

proc GUI_song_label { w } {
	variable currentsong 
	label $w -text "SONG TITLE"
	if [ info exists currentsong(file) ] {
		$w configure -text $currentsong(file)
	}
	bind $w <<mp-status-song>> [ namespace code {
		puts "----- song changed ----"
		after idle [ namespace current]::currentsong
	} ]
	bind $w <<mp-currentsong-file>> [ namespace code {
		puts "---- label $evdata(<<mp-currentsong-file>>) ---"
		%W configure -text $evdata(<<mp-currentsong-file>>)
	} ]
	puts "song widget $w"
	return $w
}
proc GUI_tag_read { w } {
	variable currentsong 
	set tx {}
	puts "---- tag read ---"
	foreach tag { Author Album Title } {
		if [ info exists currentsong($tag) ] {
			set cnv [ encoding convertfrom cp1251 $currentsong($tag) ]
			lappend tx "$tag: $cnv"
		}
	}
	$w configure -text [ join $tx \n ]
}

proc GUI_metatag { w } {
	variable currentsong 
	label $w -text "no known tag found"
	set tx {}
	foreach tag { Author Album Title } {
		if [ info exists currentsong($tag) ] {
			lappend tx "$tag: $currentsong($tag)"
		}
	}
	$w configure -text [ join $tx \n ]
	update idletasks
	bind $w <<mp-status-song>> [ list [ namespace current ]::GUI_tag_read $w ]
	return $w
}

proc GUI_volume_scale { w } {
	variable status
	scale $w -orient vert \
		-showvalue 0 \
		-from 100 \
		-to 0 
	after idle $w configure \
		-command [namespace current]::GUI_volume_timed
	if [ info exists status(volume) ] {
		after idle $w set $status(volume)
	}		
	bind $w <<mp-status-volume>> [ namespace code {
		puts "volume updated"
		$widget(volume) set $evdata(<<mp-status-volume>>)
	} ]
	return $w
}

proc GUI_position_scale_set { w value } {
	variable status
	variable position_id
	puts "SEEK TO $value"
	set position_id {}
	puts "seek $status(song) $value"
	seek $status(song) $value
}

proc GUI_position_scale_cmd { w value } {
	variable position_id 
	variable status
	variable position_fake
	if { $position_fake || $status(state) != "play" } {
		return
	}
	if { $position_id != {} } {
		catch { after cancel $position_id }
		set position_id {}
	}
	if { $value != [ lindex [ split status(time) : ] 0 ] } {
		set position_id [ after 1000 [ namespace current ]::GUI_position_scale_set $w $value ]
	}
}

proc GUI_position_timed { w } {
	return
	variable status
	variable position_fake
	variable position_timed
	variable position_id
	if { $position_id == {} || $status(state) == "play" } {
		catch {
			set curr [ $w get ]
			set position_fake 1
			$w set [ expr $curr + 1 ]
		}
		after idle [ namespace code { set position_fake 0 } ]
	}
	set position_timed [ after 1000 [ list [namespace current]::GUI_position_timed $w ] ]
}

proc GUI_position_scale { w } {
	variable position_id
	variable current_song
	variable position_fake
	variable position_timed
	set position_id {}
	scale $w -orient hor \
		-showvalue 0
	if [ info exists currentsong(Time) ] {
		$w configure -to $currentsong(Time)
		$w set $currentsong(Pos)
	}
	set position_fake 1
	after 100 [ list $w configure \
		-command [ list [ namespace current ]::GUI_position_scale_cmd $w ] ]
	after 1000 [ namespace code { set position_fake 0 } ]
	bind $w <<mp-status-time>> [ namespace code {
		if { $position_id == {} } {
			set sp [ split $evdata(<<mp-status-time>>) : ]
			set current [ lindex $sp 0 ]
			set total [ lindex $sp 1 ]
			set position_fake 1
			%W configure -to $total
			%W set $current
			after idle [ namespace code { set position_fake 0 } ]
		}
	} ]
	bind $w <<mp-status-state>> [ namespace code {
		if { $status(state) == "play" } {
			%W configure -state normal
		} else {
			%W configure -state disabled
		}
	} ]
#	set position_timed [ after 1000 [ list [namespace current]::GUI_position_timed $w ] ]
	return $w
}

proc GUI_next_button { w } {
	button $w -text "Next" -command [ namespace code next ]
	return $w
}

proc GUI_prev_button { w } {
	button $w -text "Prev" -command [ namespace code prev ]
	return $w
}

proc GUI_random_checkbutton { w } {
	variable GUI_random_checkbutton
	checkbutton $w -text "Random" \
		-onvalue 1 \
		-offvalue 0 \
		-variable [namespace current]::GUI_random_checkbutton \
		-command [ namespace code {
			if [ info exists status(random) ] {
				random [ expr ! $status(random) ]
			}
		} ]
	bind $w <<mp-status-random>> [ namespace code {
		if { $evdata(<<mp-status-random>>) } {
			# %W select
			set GUI_random_checkbutton 1
		} else {
			# %W deselect
			set GUI_random_checkbutton 0
		}
	} ]
	return $w	
}

proc GUI_shuffle_button { w } {
	button $w -text "Shuffle" -command [ namespace code shuffle ]
	return $w
}

proc GUI_repeat_checkbutton { w } {
	variable GUI_repeat_checkbutton
	checkbutton $w -text "Repeat" \
		-onvalue 1 \
		-offvalue 0 \
		-variable [namespace current]::GUI_repeat_checkbutton \
		-command [ namespace code {
			if [ info exists status(repeat) ] {
				repeat [ expr ! $status(repeat) ]
			}
		} ]
	bind $w <<mp-status-repeat>> [ namespace code {
		if { $evdata(<<mp-status-repeat>>) } {
			# %W select
			set GUI_repeat_checkbutton 1
		} else {
			# %W deselect
			set GUI_repeat_checkbutton 0
		}
	} ]
	return $w	
}
proc GUI_crossfade_cmd { w value } {
	puts "CROSSFADE $value"
	crossfade $value
}

proc GUI_crossfade_spinbox { w } {
	spinbox $w \
		-from -50 \
		-to 50 \
		-command [ namespace code {
			GUI_crossfade_cmd $w %s
		} ]
	bind $w <<mp-status-xfade>> [ namespace code {
		%W set $evdata(<<mp-status-xfade>>)
	} ]
	return $w
}

proc GUI_redirect_button { w } {
	button $w -text "" -width 1 \
		-highlightthickness 0 \
		-padx 0 -pady 0 \
		-command [ list [namespace current]::ChangeRedirect $w ]
	return $w	
}

proc GUI_std { w } {
	variable widget
	set widget(toplevel) $w
	toplevel $w
	frame $w.decor -relief raised -borderwidth 3
	pack $w.decor -fill both -expand yes
	set decor $w.decor
	set widget(song) [ GUI_song_label $decor.song ]
	grid $widget(song) \
		-row 0 -column 1 -sticky "ew"
	set widget(metatag) [ GUI_metatag $decor.metatag ]
	grid $widget(metatag) \
		-row 1 -column 1 -sticky "ew"
		
	grid [ set widget(position) [ GUI_position_scale $decor.position ] ] \
		-row 2 -column 1 -sticky "ew"
	set b $w.decor.buttons	
	frame $b -relief raised -borderwidth 3
	grid $b \
		-row 3 -column 1 -sticky "ew"
	foreach key { prev play pause stop next } {
		set widget($key) [ GUI_${key}_button $b.$key ]
		pack $widget($key) -side left -fill x -expand yes
	}
	set b $decor.option
	frame $b -relief raised -borderwidth 3
	grid $b \
		-row 4 -column 1 -sticky "ew"
	set widget(random) [ GUI_random_checkbutton $b.random ]
	set widget(repeate) [ GUI_repeat_checkbutton $b.repeate ]
	set widget(crossfade) [ GUI_crossfade_spinbox $b.crossfade ]
	pack $widget(random) $widget(repeate) $widget(crossfade) \
		-side left -fill x -expand yes
		
	set widget(playlist) [ GUI_playlist_listbox $decor.playlist ]
	grid $widget(playlist) -row 4 -column 1 -columnspan 2 -sticky "nsew"
	
	set widget(redirect) [ GUI_redirect_button $decor.redirect ]
	grid $widget(redirect) \
		-row 0 -column 2
	set widget(volume) [ GUI_volume_scale $decor.volume ]
	grid $widget(volume) \
		-row 1 -column 2 -rowspan 3 -sticky "ns"
	update idletasks	
	return $w		
}

proc GUI { w } {
	variable widget
	set widget(toplevel) $w
	bind Frame <Double-1> [ list [namespace current]::ChangeRedirect $w ]
	bind Frame <ButtonPress-1> [ list [namespace current]::StartDrag $w %X %Y ]
	bind Frame <Button1-Motion> [ list [namespace current]::Drag $w %X %Y %b ]
	frame $w -relief groove -borderwidth 3
	set widget(position) [ GUI_position_scale $w.position ]
	set widget(song) [ GUI_song_label $w.song ]
   set widget(volume) [ GUI_volume_scale $w.volume ]
	set widget(play) [ GUI_play_button $w.play ]
	set widget(stop) [ GUI_stop_button $w.stop ]
	set widget(pause) [ GUI_pause_button $w.pause ]
	set widget(next) [ GUI_next_button $w.next ]
	set widget(prev) [ GUI_prev_button $w.prev ]
	set widget(shuffleButton) $w.shuffle
	set widget(random) [ GUI_random_checkbutton $w.random ]
	set widget(repeat) [ GUI_repeat_checkbutton $w.repeat ]
	set widget(shuffle) [ GUI_shuffle_button $w.shuffle ]
	set widget(crossfade) [ GUI_crossfade_spinbox $w.crossfade ]	
	set widget(playlist) [ GUI_playlist_listbox $w.playlist ]
	pack $w.song \
		$w.volume \
		$w.position \
		$w.play \
		$w.stop \
		$w.pause \
		$w.next \
		$w.prev \
		$w.random \
		$w.repeat \
		$w.shuffle \
		$w.crossfade \
		$w.playlist
		
	return $w		
}



#############################################
#############################################
###
###   PLAYLIST
###
#############################################
#############################################
proc GUI_playlist_reread { w } {
	variable playlist
	variable playlistinfo
	variable status
	variable playlist_song_id
	puts "----- REREAD PLAYLIST ----"
	catch { array unset playlist_song_pos }
	$w.ls delete 0 end
	set pos 0
	playlistinfo
	foreach id $playlist {
		$w.ls insert end $playlistinfo($id,file)
		set playlistinfo($id,listpos) $pos
		set playlist_song_id($pos) $playlistinfo($id,Pos)
		incr pos
	}
	set curr $playlistinfo($status(songid),listpos)
	$w.ls see $curr
	$w.ls activate $curr
	$w.ls itemconfigure $curr -background green
}

proc GUI_playlist_songchanged { w evname } {
	variable evdata
	variable playlistinfo
	variable status
	variable playlist_pos
	puts "------ SONG--------"
	catch {
		$w.ls itemconfigure $playlist_pos -background {}
	}
	if [ info exists playlistinfo($evdata($evname),listpos) ] {
		set curr $playlistinfo($evdata($evname),listpos)
		$w.ls see $curr
		$w.ls activate $curr
		$w.ls itemconfigure $curr -background green
		set playlist_pos $curr
	}
	$w.ls selection clear 0 end
}

proc GUI_playlist_dblclick { w W x y } {
	variable playlist_song_id
	puts "DBL_CLICK"
	set pos [ $W index @$x,$y ]
	if { $pos == {} || $pos == -1 || ! [ array exists playlist_song_id ] } {
		puts "FAULT 1 pos = $pos"
		return
	}
	if [ info exists playlist_song_id($pos) ] {
		seek $playlist_song_id($pos) 0
		puts "DBL :: seek $playlist_song_id($pos) 0"
	}	
}

proc GUI_playlist_listbox { w } {
	frame $w -relief raised -borderwidth 3
	label $w.name
	listbox $w.ls \
		-xscrollcommand [ list $w.hscroll set ] \
		-yscrollcommand [ list $w.vscroll set ] \
		-selectmode browse
	scrollbar $w.hscroll -orient hor \
		-command [ list $w.ls xview ]
	scrollbar $w.vscroll -orient vert \
		-command [ list $w.ls yview ]
	grid $w.name -column 0 -row 0 -sticky "ew"
	grid $w.ls -column 0 -row 1 -sticky "nsew"
	grid $w.vscroll -row 1 -column 1 -sticky "ns"
	grid $w.hscroll -row 2 -column 0 -sticky "ew"
	grid columnconfigure $w 0 -weight 1
	grid rowconfigure $w 1 -weight 1
	bind $w.ls <Double-Button-1> \
		[ list [namespace current]::GUI_playlist_dblclick $w %W %x %y ]
	bind $w <<mp-status-playlist>> \
		[ list after 100 [ list [namespace current]::GUI_playlist_reread $w ] ]
	bind $w <<mp-status-songid>> \
		[ list after 100 [ list [namespace current]::GUI_playlist_songchanged $w <<mp-status-songid>> ] ]
	puts "LISTNOX DONE"
	return $w
}

bind Frame <Double-1> [ list [namespace current]::ChangeRedirect %W ]
bind Frame <ButtonPress-1> [ list [namespace current]::StartDrag %W %X %Y ]
bind Frame <Button1-Motion> [ list [namespace current]::Drag %W %X %Y %b ]
bind Label <Double-1> [ list [namespace current]::ChangeRedirect %W ]
bind Label <ButtonPress-1> [ list [namespace current]::StartDrag %W %X %Y ]
bind Label <Button1-Motion> [ list [namespace current]::Drag %W %X %Y %b ]
bind Label <Control-1> {
	variable gui_color
	if { ! [ info exists gui_color ] } {
		set gui_color [ . cget -background ]
	}
	set gui_color [ tk_chooseColor -initialcolor $gui_color]
	if { $gui_color != {} } {
		puts "color : $gui_color"
		tk_setPalette $gui_color
	}
}
}; # end-of-namespace
set w [ MPClient::GUI_std .mp ]
wm deiconify $w
puts "[after info]"
after 100
puts "FIRST UPDATE"
update

MPClient::connect
puts "DO connect"
puts "connected"
MPClient::song_timer
# wm withdraw .
puts "DO UPDATE"
update
puts "WAITED"
tkwait window .mp
exit

