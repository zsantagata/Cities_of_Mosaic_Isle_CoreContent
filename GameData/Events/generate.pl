use warnings;
use strict;
use Cwd;
use Spreadsheet::Read;
use Scalar::Util;

my $debug = 1; #0 is off

#TODO: This spreadsheet should prepend the 'name' field with the name of the file being calculated (without the .ods extension)

#in order:
#1) detect all .ods files and store their names
#2) load an .ods file
#3) load values from the appropriate rows for a single event
#4) do checking that the values from an event make sense
#5) write the event's xml to the internal buffer
#6) if there are more appropriate rows, jump to 3)
#7) write out an xml file
#8) if there are more .ods files, jump to #2

sub checkName{
	my $name = shift;
	if($name eq "default")
	{
		die "An event's name cannot be the default name \"default\"";
	}
	if($name eq "")
	{
		die "An event's name cannot be the empty string";
	}
}

sub checkType{
	my $type = shift;
	my $delType = shift;
	if(($type >= 4) or ($type < 0))
	{
		die "Type must be 0 through 3 inclusive";
	}
	if(($type == 1) and ($delType == 0))
	{
		die "Delegation type must not be 0 when type is Arrival";
	}
	if((($type == 0) or ($type == 3)) and ($delType != 0))
	{
		die "Delegation type must be 0 when type is Normal or Simultaneous";
	}
}

sub checkSimultaneous{
	my $type = shift;
	my $simultaneous = shift;
	my $simultaneous_is_zero = (Scalar::Util::looks_like_number($simultaneous));
	if($simultaneous_is_zero)
	{
		$simultaneous_is_zero = ($simultaneous == 0);
	}
	if($type != 3)
	{
		if($simultaneous_is_zero)
		{
		}
		else
		{
			die "Simultaneous must be 0 when type is not 3";
		}
	}
	elsif($simultaneous_is_zero)
	{
		die "Simultaneous must not be 0 when type is 3";
	}
}

sub checkProbability{
	my $type = shift;
	my $weight = shift;
	if($weight < 0)
	{
		die "MTTH or weight may not be negative";
	}
	if(($type == 1) or ($type == 3))
	{
		if($weight == 0)
		{
			die "weight may not be 0";
		}
	}
}

sub checkChoiceCount{
	my $invis = shift;
	my $choiceCt = shift;
	
	my $is_invis = !($invis == 0);
	if(($is_invis) and ($choiceCt != 0))
	{
		die "choice count must be 0 when the event is invisible";
	}
	elsif(!($is_invis) and ($choiceCt == 0))
	{
		die "choice count must not be 0 when the event is not invisible";
	}
}

sub checkMenuText{
	my $invis = shift;
	my $menuText = shift;
	
	my $is_invis = !($invis == 0);
	if(!($is_invis) and (($menuText eq "") or ($menuText eq "N/A") or ($menuText eq "n/a")))
	{
		die "menuText must not be blank when the event is not invisible";
	}
}

sub checkChoice{
	my $choiceName = shift;
	my $choiceGatingScript = shift;
	my $prediction = shift;
	my $hoverOverText = shift;
	my $resolutionText = shift;
	
	if(($choiceName eq "") or ($choiceGatingScript eq "") or ($hoverOverText eq "") or ($resolutionText eq ""))
	{
		die "a choice must have name, gating script, hover over text, and resolution text that are not empty string";
	}
	if(($prediction < 0) or ($prediction > 100))
	{
		die "Prediction difficulty may not be below 0 or above 100";
	}
}

sub cleanUpForXML{
	my $string = shift;
	if(not defined $string)
	{
		return "";
	}
	$string =~ s/\&/\&amp;/g; #this one should be first
	$string =~ s/\</\&lt;/g;
	$string =~ s/\>/\&gt;/g;
	$string =~ s/\'/\&apos;/g;
	$string =~ s/\"/\&quot;/g;
	return $string;
}

my @writeOutLines = ();

sub writeEventToLines{
	my $eventInternalName = shift;
	my $eventDisplayName = shift;
	my $eventTags = shift;
	my @tags = split(/, /, $eventTags);
	#variable text is not fed into this function
	my $eventType = shift;
	my $eventSimultaneous = shift;
	my $eventEnabled = shift;
	my $eventProb = shift;
	my $eventInvisible = shift;
	my $eventStopTime = shift;
	my $eventCanHappenWhile  = shift;
	my $eventDelegationType = shift;
	my $eventMenuText = shift;
	my $eventGatingScript = shift;
	my $eventUponHappeningScript = shift;
	my $eventChoiceNamesRef = shift;
	
	if($debug != 0)
	{
		print "Value of eventInternalName=" . $eventInternalName . "\n";
		print "Value of eventDisplayName=" . $eventDisplayName . "\n";
		print "Value of eventTags=" . (@tags) . "\n";
		print "Value of eventType=" . $eventType . "\n";
		print "Value of eventSimultaneous=" . $eventSimultaneous . "\n";
		print "Value of eventEnabled=" . $eventEnabled . "\n";
		print "Value of eventProb=" . $eventProb . "\n";
		print "Value of eventInvisible=" . $eventInvisible . "\n";
		print "Value of eventStopTime=" . $eventStopTime . "\n";
		print "Value of eventCanHappenWhile=" . $eventCanHappenWhile . "\n";
		print "Value of eventDelegationType=" . $eventDelegationType . "\n";
		print "Value of eventMenuText=" . $eventMenuText . "\n";
		print "Value of eventGatingScript=" . $eventGatingScript . "\n";
		print "Value of eventUponHappeningScript=" . $eventUponHappeningScript . "\n";
		print "Value of eventChoiceNamesRef=" . $eventChoiceNamesRef . "\n";
	}
	
	my @eventChoiceNames = @{$eventChoiceNamesRef};
	my $eventChoiceGatingScriptsRef = shift;
	my @eventChoiceGatingScripts = @{$eventChoiceGatingScriptsRef};
	my $eventChoiceSelectionScriptsRef = shift;
	my @eventChoiceSelectionScripts = @{$eventChoiceSelectionScriptsRef};
	my $eventPredictionDifficultiesRef = shift;
	my @eventPredictionDifficulties = @{$eventPredictionDifficultiesRef};
	my $eventHoverOverTextsRef = shift;
	my @eventHoverOverTexts = @{$eventHoverOverTextsRef};
	my $eventResolutionTextsRef = shift;
	my @eventResolutionTexts = @{$eventResolutionTextsRef};
	
	if($debug != 0)
	{
		print "Value of eventChoiceNames=" . (@eventChoiceNames) . "\n";
		print "Value of eventChoiceGatingScripts=" . (@eventChoiceGatingScripts) . "\n";
		print "Value of eventChoiceSelectionScripts=" . (@eventChoiceSelectionScripts) . "\n";
		print "Value of eventPredictionDifficulties=" . (@eventPredictionDifficulties) . "\n";
		print "Value of eventHoverOverTexts=" . (@eventHoverOverTexts) . "\n";
		print "Value of eventResolutionTexts=" . (@eventResolutionTexts) . "\n";
	}
	
	checkName($eventInternalName);
	checkType($eventType, $eventDelegationType);
	checkSimultaneous($eventType, $eventSimultaneous);
	checkProbability($eventType, $eventProb);
	checkMenuText($eventInvisible, $eventMenuText);
	checkChoiceCount($eventInvisible, scalar(@eventChoiceNames));
	
	push @writeOutLines, "  <igEvent name=\"" . cleanUpForXML($eventInternalName) . "\" display_name=\"" . cleanUpForXML($eventDisplayName) . "\">";
	push @writeOutLines, "    <mTagList>";
	foreach my $tag (@tags)
	{
		push @writeOutLines, "      <i>" . cleanUpForXML($tag) . "</i>";
	}
	push @writeOutLines, "    </mTagList>";
	push @writeOutLines, "";
	push @writeOutLines, "    <mTypeOfEvent>" . $eventType . "</mTypeOfEvent>";
	push @writeOutLines, "    <mSimultaneousWithOccurrence>" . $eventSimultaneous . "</mSimultaneousWithOccurrence>";
	push @writeOutLines, "    <mDefaultEnabled>" . $eventEnabled . "</mDefaultEnabled>";
	push @writeOutLines, "    <mDelegationType>" . $eventDelegationType . "</mDelegationType>";
	if(($eventType == 0) or ($eventType == 2))
	{
		push @writeOutLines, "    <mDefaultMTTH>" . $eventProb . "</mDefaultMTTH>";
	}
	else
	{
		push @writeOutLines, "    <mDefaultWeight>" . $eventProb . "</mDefaultWeight>";
	}
	push @writeOutLines, "";
	push @writeOutLines, "    <mScriptWhichGatesHappening>\n" . cleanUpForXML($eventGatingScript) . "\n    </mScriptWhichGatesHappening>";
	push @writeOutLines, "";
	push @writeOutLines, "    <mScriptUponHappening>\n" . cleanUpForXML($eventUponHappeningScript) . "\n    </mScriptUponHappening>";
	push @writeOutLines, "";
	push @writeOutLines, "    <mDefaultMenuText>\n" . cleanUpForXML($eventMenuText) . "\n    </mDefaultMenuText>";
	push @writeOutLines, "    <mInvisible>" . $eventInvisible . "</mInvisible>";
	push @writeOutLines, "    <mStopTimeAndForceEvaluate>" . $eventStopTime . "</mStopTimeAndForceEvaluate>";
	push @writeOutLines, "    <mCanHappenWhileReportPending>" . $eventCanHappenWhile . "</mCanHappenWhileReportPending>";
	
	push @writeOutLines, "";
	my $maxCt = scalar(@eventChoiceNames);
	my $iterator = 0;
	push @writeOutLines, "    <mChoiceCombo>";
	while($iterator < $maxCt)
	{
		checkChoice($eventChoiceNames[$iterator], $eventChoiceGatingScripts[$iterator], $eventPredictionDifficulties[$iterator], $eventHoverOverTexts[$iterator], $eventResolutionTexts[$iterator]);
		
		push @writeOutLines, "      <i>";
		
		push @writeOutLines, "        <name>" . cleanUpForXML($eventChoiceNames[$iterator]) . "</name>";
		push @writeOutLines, "        <appears_script>\n" . cleanUpForXML($eventChoiceGatingScripts[$iterator]) . "\n        </appears_script>";
		push @writeOutLines, "        <selection_script>\n" . cleanUpForXML($eventChoiceSelectionScripts[$iterator]) . "\n        </selection_script>";
		push @writeOutLines, "        <predict_diff>" . $eventPredictionDifficulties[$iterator] . "</predict_diff>";
		push @writeOutLines, "        <prechoice>\n" . cleanUpForXML($eventHoverOverTexts[$iterator]) . "\n        </prechoice>";
		push @writeOutLines, "        <resolution>\n" . cleanUpForXML($eventResolutionTexts[$iterator]) . "\n        </resolution>";
		
		push @writeOutLines, "      </i>";
		$iterator = $iterator + 1;
	}
	push @writeOutLines, "    </mChoiceCombo>";
	push @writeOutLines, "  </igEvent>\n";
}

#example of passing arrays as arguments:
#my @sums = two_array_sum(\@aArray, \@bArray);
#sub two_array_sum { # two_array_sum ( (1 2 3 4), (2, 4, 0, 1) ) -> (3, 6, 3, 5)
#    my ($aRef, $bRef) = @_;
#    my @result = ();

#    my $idx = 0;
#    foreach my $aItem (@{$aRef}) {
#        my $bItem = $bRef->[$idx++];
#        push (@result, $aItem + $bItem);
#    }

opendir(D, "./") or die "Could not open this directory\n";
my @list = readdir(D);
closedir(D);

my @odsFiles = ();

foreach my $file (@list)
{
	if($debug != 0)
	{
		print "Checking if file $file is an ods file\n";
	}
	if($file =~ /\.ods/)
	{
		push @odsFiles, $file;
		if($debug != 0)
		{
			print "file $file is an ods file\n";
		}
	}
	else
	{
		if($debug != 0)
		{
			print "file $file is not an ods file\n";
		}
	}
}

foreach my $odsFile (@odsFiles)
{
	push @writeOutLines, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>";
	push @writeOutLines, "<!-- The above is a default, but its inclusion should be everywhere just to indicate that all files, for our purposes, are UTF-8 encoded.  Also, as a reminder, the less than, greater than, ampersand, apostrophe, and quotation mark are invalid XML and must be replaced with the literal text &lt; &gt; &amp; &apos; &quot; with the semicolons -->";
	push @writeOutLines, "<core_data>";

	my $ss = ReadData($odsFile, parser => "ods")->[1]; #NOTE TO SELF: each file should have only one sheet; all other sheets besides the first are ignored
	
    my $row = 2; #skip the first row, it's labels
	my $empty_row = 0;
	
	#event variables (used in loop below, stored between iterations):
	my $eventInternalName = "";
	my $eventDisplayName = "";
	my $eventTags = "";
	my $eventType = 0;
	my $eventSimultaneous = 0;
	my $eventEnabled = 0;
	my $eventProb = 0;
	my $eventInvisible = 0;
	my $eventStopTime = 0;
	my $eventCanHappenWhile = 0;
	my $eventDelegationType = 0;
	my $eventMenuText = "";
	my $eventGatingScript = "";
	my $eventUponHappeningScript = "";
	my @eventChoiceNames = ();
	my @eventChoiceGatingScripts = ();
	my @eventChoiceSelectionScripts = ();
	my @eventPredictionDifficulties = ();
	my @eventHoverOverTexts = ();
	my @eventResolutionTexts = ();
	
	while($empty_row == 0)
	{
		if((not defined $ss->{cell}[1][$row]) and (not defined $ss->{cell}[18][$row])) #if there is no event name and no choice name
		{
			$empty_row = 1;
			#write the current values to @writeOutLines
			if(!($eventInternalName eq ""))
			{
				writeEventToLines($eventInternalName, $eventDisplayName, $eventTags, $eventType, $eventSimultaneous, $eventEnabled, $eventProb, $eventInvisible, $eventStopTime, $eventCanHappenWhile, $eventDelegationType, $eventMenuText, $eventGatingScript, $eventUponHappeningScript, \@eventChoiceNames, \@eventChoiceGatingScripts, \@eventChoiceSelectionScripts, \@eventPredictionDifficulties, \@eventHoverOverTexts, \@eventResolutionTexts);
			}
		}
		else
		{
			my $anotherChoice = (not defined $ss->{cell}[1][$row]); #if the event name is empty, this must be another choice of the current event
			if(not $anotherChoice)
			{
				#write the current values to @writeOutLines
				if(!($eventInternalName eq ""))
				{
					writeEventToLines($eventInternalName, $eventDisplayName, $eventTags, $eventType, $eventSimultaneous, $eventEnabled, $eventProb, $eventInvisible, $eventStopTime, $eventCanHappenWhile, $eventDelegationType, $eventMenuText, $eventGatingScript, $eventUponHappeningScript, \@eventChoiceNames, \@eventChoiceGatingScripts, \@eventChoiceSelectionScripts, \@eventPredictionDifficulties, \@eventHoverOverTexts, \@eventResolutionTexts);
					
					#clear existing values:
					$eventInternalName = "";
					$eventDisplayName = "";
					$eventTags = "";
					$eventType = 0;
					$eventSimultaneous = 0;
					$eventEnabled = 0;
					$eventProb = 0;
					$eventInvisible = 0;
					$eventStopTime = 0;
					$eventCanHappenWhile = 0;
					$eventMenuText = "";
					$eventGatingScript = "";
					$eventUponHappeningScript = "";
					@eventChoiceNames = ();
					@eventChoiceGatingScripts = ();
					@eventChoiceSelectionScripts = ();
					@eventPredictionDifficulties = ();
					@eventHoverOverTexts = ();
					@eventResolutionTexts = ();
				}
				
				#read event data from this row before the choice:
				#note that the spreadsheets contain summaries and therefore some columns are skipped
				$eventInternalName = $ss->{cell}[1][$row];
				$eventDisplayName = $ss->{cell}[2][$row];
				$eventTags = $ss->{cell}[4][$row];
				$eventType = $ss->{cell}[6][$row];
				$eventSimultaneous = $ss->{cell}[7][$row];
				$eventEnabled = $ss->{cell}[8][$row];
				$eventProb = $ss->{cell}[9][$row];
				$eventInvisible = $ss->{cell}[10][$row];
				$eventStopTime = $ss->{cell}[11][$row];
				$eventCanHappenWhile = $ss->{cell}[12][$row];
				$eventDelegationType = $ss->{cell}[13][$row];
				
				$eventMenuText = $ss->{cell}[15][$row];
				$eventGatingScript = $ss->{cell}[16][$row];
				$eventUponHappeningScript = $ss->{cell}[17][$row];
			}
			#if the event is invisible, skip the rest of the row
			if($eventInvisible == 0)
			{
				#note that the spreadsheets contain summaries and therefore some columns are skipped
				push @eventChoiceNames, ($ss->{cell}[18][$row]);
				push @eventChoiceGatingScripts, ($ss->{cell}[20][$row]);
				push @eventChoiceSelectionScripts, ($ss->{cell}[21][$row]);
				push @eventPredictionDifficulties, ($ss->{cell}[22][$row]);
				push @eventHoverOverTexts, ($ss->{cell}[23][$row]);
				push @eventResolutionTexts, ($ss->{cell}[25][$row]);
			}
		}
		$row = $row + 1;
	}
	push @writeOutLines, "</core_data>";
	
	my $outfilename = $odsFile;
	$outfilename =~ s/\.ods/\.xml/;
	open(FILEH, ">", "./" . $outfilename) or die "Could not open output file for writing\n";
	foreach my $line (@writeOutLines)
	{
		print FILEH $line . "\n";
	}
	close FILEH;
	
	@writeOutLines = ();
}