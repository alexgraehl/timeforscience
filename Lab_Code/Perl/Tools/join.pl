#!/usr/bin/perl -w

#@COMMENT@ join.pl is a modified version of UNIX join. It can handle un-sorted input and deal with case-insensitive joins. It behaves in a manner that is more similar to what you would expect from a database join. If you want to join multiple files at once, see "join_multi.pl". Frequency-of-use rating: 10/10.

# New version of join.pl by Alex Williams. (This isn't related to the previous UCSC code at all... and probably produces different results! Note that both versions will occasionally produce different results from UNIX join, even on properly sorted input!) UNIX join maybe does the cartesian product sometimes? Anyway, it's probably not what you want.

# Nov 10, 2015: handles Mac '\r'-only input files better. Previously had a bug and output additional "no match" entries no matter what. Whoops, this broken in certain cases. Now it just errors out no matter what if it sees a '\r'
# Now 24, 2015: --multi=intersect added. Now works for multi-file joining (3 or more files).

use strict; use warnings; use Getopt::Long;
#use File::Slurp; # <-- for reading an entire file into memory.
# If the system doesn't have slurp, then:
#  sudo perl -MCPAN -e shell
#  install File::Slurp

use Term::ANSIColor;
$| = 1;  # Flush output to STDOUT immediately.

my $isDebugging = 0;
my $verbose = 1; # use 'q' (quiet) to suppress this

sub quitWithUsageError($) { print STDOUT ($_[0] . "\n"); printUsageAndContinue(); warn($_[0] . "\n"); exit(1); }
sub printUsageAndQuit() { printUsageAndContinue(); exit(1); }
sub printUsageAndContinue() {    print STDOUT <DATA>; }
sub debugPrint($) {   ($isDebugging) and print STDERR $_[0]; }
sub verboseWarnPrint($) { if ($verbose) { print STDERR Term::ANSIColor::colored($_[0] . "\n", "yellow on_blue"); } }
sub verboseUpdatePrint($) { if ($verbose) { print STDERR Term::ANSIColor::colored($_[0] . "\n", "black on_green"); } }
my $keyCol1 = undef; # indexed from ONE rather than 0!
my $keyCol2 = undef; # indexed from ONE rather than 0!

my $DEFAULT_DELIM = "\t";
my $SPLIT_WITH_TRAILING_DELIMS = -1; # You MUST specify this constant value of -1, or else split will by default NOT split consecutive trailing delimiters! This is super important and belongs in EVERY SINGLE split call.
my $MAX_DUPE_KEYS_TO_REPORT          = 10;
my $MAX_WEIRD_LINE_LENGTHS_TO_REPORT = 10;
my $MAX_BLANK_LINES_TO_REPORT        = 10;
my $MAX_WHITESPACE_KEYS_TO_REPORT    = 50;
my $MAX_MISSING_KEY_COLS_TO_REPORT   = 10;

my $UNION_STR     = "union";
my $INTERSECT_STR = "intersect";

# Global I guess
my $numDupeKeysMultiJoin   = 0;
my $numBlankLines          = 0;
my $numWeirdLengths        = 0;
my $numMissingKeyCols      = 0;
my $numWhitespaceKeys      = 0;
my $numWeirdLineLengths    = 0;

my $delim1            = $DEFAULT_DELIM; # input deilmiter for file 1
my $delim2            = $DEFAULT_DELIM; # input delimiter for file 2
my $delimBoth         = undef; # input delimiter
my $outDelim       = undef;
my $shouldNegate      = 0; # whether we should NEGATE the output
my $shouldIgnoreCase  = 0; # by default, case-sensitive
my $stringWhenNoMatch = undef;
my $allowEmptyKey     = 0; # whether we allow a TOTALLY EMPTY value to be a key (default: no)
#my $preserveKeyOrder  = 0; # whether we should KEEP the key in whatever column it was found in, instead of moving it to the front of the line.
my $numHeaderLines    = 0;
my $multiJoinType     = undef;
my $includeFilenameInHeader = 0;

#my $shouldReverse     = 0; # Should we print KEY FILE2 FILE1? Default is KEY FILE1 FILE2.

my $sumDuplicates  = 0; # if multiple keys are seen in ONE FILE, try to SUM them.

my $keyBoth = undef;

sub guess_multi_join_type_from_parameters($$$) {
	my ($specified_join_type, $num_input_files, $missing_value_string) = @_;

	if (!defined($specified_join_type)) {
		if ($num_input_files >= 3) {
			quitWithUsageError("You must specify a join type, either '--multi=union' or '--multi=intersect', if you supply 3 or more files to join. Re-run the command with --multi=i or --multi=u");
		} elsif ($num_input_files == 2) {
			$specified_join_type = defined($missing_value_string) ? $UNION_STR : $INTERSECT_STR;
		}
	}
	if (defined($specified_join_type)) {
		if ($specified_join_type =~ m/^u/i)    { $specified_join_type = $UNION_STR; }
		elsif ($specified_join_type =~ m/^i/i) { $specified_join_type = $INTERSECT_STR; }
		else { quitWithUsageError("Unrecognized --multi value: must be either 'union' or 'intersect' (or 'u' or 'i'). Your invalid value was: $specified_join_type"); }
	}
	if (defined($specified_join_type) and ($specified_join_type eq $INTERSECT_STR) and defined($missing_value_string)) {
		quitWithUsageError("You cannot specify a 'string when there is no match' value when you are doing an INTERSECTION. This value would never be used. Remove the '-o' or '--ob' arguments!");
	}
	return $specified_join_type;
}

$Getopt::Long::passthrough = 1; # ignore arguments we don't recognize in GetOptions, and put them in @ARGV
GetOptions("help|?|man" => sub { printUsageAndQuit(); }
	   , "k=i" => \$keyBoth
	   , "f=i" => sub { quitWithUsageError("-f is not an option to this script! If you want to specify field separators, use -d (delim). If you want to specify keys, use -1 and -2 to pick the key columns.\n"); }
	   , "q" => sub { $verbose = 0; } # q = quiet
	   , "1=s" => \$keyCol1
	   , "2=s" => \$keyCol2
	   , "d1=s" => \$delim1
	   , "d2=s" => \$delim2
	   , "t|d|delim=s" => \$delimBoth # -t is the regular UNIX join name for this option
	   , "o=s"  => \$stringWhenNoMatch # -o "0.00" would be "print 0.00 for missing values"
	   , "ob!"  => sub { $stringWhenNoMatch = ''; } # shortcut for just a blank when there's no match. Default is to OMIT lines with no match.
	   , "do=s" => \$outDelim
	   , "v|neg!" => \$shouldNegate
#	   , "sum|sum-duplicates!" => \$sumDuplicates # for numeric values, we can also SUM the duplicate values on a per-file basis instead of just overwriting them
	   , "h|header|headers=i" => \$numHeaderLines
	   , "fnh|filename-in-header" => \$includeFilenameInHeader # only for multi-join
#	   , "nrk|no-reorder-key!"  => \$preserveKeyOrder
	   , "eok|allow-empty-key!" => \$allowEmptyKey # basically, do we skip blank lines?
	   , "i|ignore-case!" => \$shouldIgnoreCase
##	   , "rev" => \$shouldReverse  # Should we print KEY FILE2 FILE1? Default is KEY FILE1 FILE2.
	   , "multi=s" => \$multiJoinType
	   , "union!"     => sub { $multiJoinType = $UNION_STR; }
	   , "intersect!" => sub { $multiJoinType = $INTERSECT_STR; }
	   , "debug!" => \$isDebugging
    ) or printUsageAndQuit();

my $numUnprocessedArgs = scalar(@ARGV);
($numUnprocessedArgs >= 2) or quitWithUsageError("[Error] in arguments! You must send at least TWO filenames (or one filename and '-' for STDIN) to this program. Example: join.pl FILE1.txt FILE2.txt > OUTPUT.txt");

my @files = @ARGV; #my ($file1,$file2) = ($files[0], $files[1]);
my $numFilesToJoin = scalar(@files);

$multiJoinType = guess_multi_join_type_from_parameters($multiJoinType, $numFilesToJoin, $stringWhenNoMatch);

if (defined($keyBoth)) {
	(!defined($keyCol1) and !defined($keyCol2)) or quitWithUsageError("You cannot specify both -k (key) AND ALSO -1 (key for file 1) or -2 (key for file 2). -k sets both -1 and -2. Pick one or the other!");
	$keyCol1 = $keyBoth; $keyCol2 = $keyBoth;
} else {
	$keyCol1 = (defined($keyCol1)) ? $keyCol1 : 1; # default value is 1
	$keyCol2 = (defined($keyCol2)) ? $keyCol2 : 1; # default value is 1
}
($keyCol1 =~ m/[0-9]+/ && $keyCol1 >= 0) or quitWithUsageError("[ERROR]: Key1 (-1 argument) to join.pl (which was specified as '$keyCol1') CANNOT BE ZERO or less than zero! These indices are numbered from ONE and not zero!");
($keyCol2 =~ m/[0-9]+/ && $keyCol2 >= 0) or quitWithUsageError("[ERROR]: Key2 (-2 argument) to join.pl (which you specified as '$keyCol2') CANNOT BE ZERO or less than zero! These indices are numbered from ONE and not zero!");

## ================ SET SOME DEFAULT VALUES ============================
if (defined($delimBoth)) { # If "delimBoth" was specified, then set both of the input delimiters accordingly.
	$delim1 = $delimBoth; $delim2 = $delimBoth;
}

if (!defined($outDelim)) { # Figure out what the output delimiter should be, if it wasn't explicitly specified.
    if (defined($delimBoth)) { $outDelim = $delimBoth; } # default: set the output delim to whatever the input delim was
    elsif ($delim1 eq $delim2) { $outDelim = $delim1; } # or we can set it to the manually-specified delimiters, if they are the SAME only
    else { $outDelim = $DEFAULT_DELIM; } # otherwise, set it to the default delimiter
}
## ================ DONE SETTING SOME DEFAULT VALUES ====================

## ================ SANITY-CHECK A BUNCH OF VARIABLES ==================
foreach my $ff (@files) {
	(-f $ff and -r $ff) or die "[ERROR]: join.pl cannot join these two files, because the file '$ff' did not exist or could not be read!"; # Specified files must be either - (for stdin) or a real, valid, existing filename)
	#(($ff eq '-') or 
}
(!$shouldNegate or !defined($stringWhenNoMatch)) or quitWithUsageError("[Error] in arguments! Cannot specify both --neg AND -o or --ob, because it doesn't make sense to both '--neg (negate)' the join AND ALSO specify '-o' or '--ob' -- the outer join specifies that we should print lines REGARDLESS of match, whereas the --neg specifies that we should ONLY print lines with no match. You cannot specifiy both of these options at the same time.");

if (defined($stringWhenNoMatch)) { # replace any "\t" with actual tabs! No idea why it doesn't work on the command line otherwise
    $stringWhenNoMatch =~ s/[\\][t]/\t/g; # replace a SINGLE backslash-then-t with a tab
    $stringWhenNoMatch =~ s/[\\][n]/\n/g; # replace a SINGLE backslash-then-n with a newline
    $stringWhenNoMatch =~ s/[\\][r]/\n/g; # replace a SINGLE backslash-then-r with a CR return
}

## ================ DONE SANITY-CHECKING A BUNCH OF VARIABLES ==================

sub maybeWarn($$$) {
	my ($weirdCount, $maxWeirdCount, $message) = @_;
	if ($weirdCount == $maxWeirdCount) { $message .= " (suppressing further warnings about this issue)"; }
	($weirdCount <= $maxWeirdCount ) and verboseWarnPrint("Warning: $message");
}

sub closeSmartFilehandle($) { my($handle)=@_; if ($handle ne *STDIN) { close $handle; } }# Don't close STDIN, but close anything else!
sub openSmartAndGetFilehandle($) {
    # returns a FILEHANDLE. Can be standard in, if the 'filename' was specified as '-'
    # Transparently handles ".gz" and ".bz2" files.
    # This is the MARCH 6, 2013 version of this function.
    my ($filename) = @_;
    if ($filename eq '-') { return(*STDIN); } # <-- RETURN!!!
    my $reader;
    if    ($filename =~ /[.](gz|gzip)$/i)  { $reader = "gzip  -d --stdout $filename |"; }    # Un-gzip a file and send it to STDOUT.
    elsif ($filename =~ /[.]bz2$/i) { $reader = "bzip2 -d -c       $filename |"; }    # Un-bz2 a file and send it to STDOUT
    elsif ($filename =~ /[.]xz$/i)  { $reader = "xz -d -c       $filename |"; }    # Un-xz a file and send it to STDOUT
    elsif ($filename =~ /[.]zip$/i) { $reader = "unzip -p $filename |"; } # Un-regular-zip a file and send it to STDOUT with "-p": which is DIFFERENT from -c (-c is NOT what you want here). See 'man unzip'
    else                            { $reader = "$filename"; }  # Default: just read a file normally
    my $fh;
    open($fh, "$reader") or die("Couldn't read from <$filename>: $!");
    return $fh;
}
	
sub readIntoHash($$$$$) {
	my ($filename, $theDelim, $keyIndexCountingFromOne, $masterHashRef, $origCaseHashRef) = @_;
	my $numDupeKeys = 0;
	my $numWhitespaceKeysThisFileOnly = 0;
	my $lineNum = 0;
	my $theFileHandle = openSmartAndGetFilehandle($filename);
	foreach my $line ( <$theFileHandle> ) {
		$lineNum++;
		#print STDERR ("Found a line... line number $lineNum\n");
		($line !~ m/\r/) or die "ERROR: Exiting! We found a '\\r' character on a line, but there should not be any backslash-r carraige return (CR) characters in the file at this point. We CANNOT properly handle this in file <$filename> on line $lineNum...!\n";
		chomp($line);
		#if(/\S/) { ## if there's some content that's non-spaces-only
		my @sp1 = split($theDelim, $line, $SPLIT_WITH_TRAILING_DELIMS);

		my $thisRowHasAKeyColumn = ($keyIndexCountingFromOne-1) < scalar(@sp1);
		if (!$thisRowHasAKeyColumn) {
			verboseWarnPrint("Warning: skipping row $lineNum, which does not have a key column AT ALL! This is often seen with comment lines at the top of a file. But it may also inicate an incorrect key column.");
			next; # next iteration of the loop please!
		}

		my $theKey = $sp1[ ($keyIndexCountingFromOne - 1) ]; # index from ZERO here!
		if (('' eq $theKey) and !$allowEmptyKey) {
			verboseWarnPrint("Warning: skipping the empty key on line $lineNum of file <$filename>!");
			next; # next iteration of the loop please!
		}

		($theKey !~ /\s/) or maybeWarn($numWhitespaceKeysThisFileOnly++, $MAX_WHITESPACE_KEYS_TO_REPORT, "on line $lineNum in file <$filename>, the key <$theKey> had *whitespace* in it. This is often unintentional, but is not necessarily a problem!");
		
		if (defined($masterHashRef->{$theKey})) {
			maybeWarn($numDupeKeys++, $MAX_DUPE_KEYS_TO_REPORT, "on line $lineNum, we saw a duplicate of key <$theKey> (in file <$filename>). We are only keeping the FIRST instance of this key.");
		} else {
			# Found a UNIQUE new key! ($isDebugging) && print STDERR "Added a line for the key <$theKey>.\n";
			# Key was valid, OR we are allowing empty keys!
			if (defined($origCaseHashRef)) {
				$origCaseHashRef->{uc($theKey)} = $theKey;
			} # maps from the UPPER-CASE version of this key (KEY) back to the one we ACTUALLY put in the hash (VALUE)
			@{$masterHashRef->{$theKey}} = @sp1; # whole SPLIT UP line, even the key, goes into the hash!!!. # masterHashRef is a hash of ARRAYS: each line is ALREADY SPLIT UP by its delimiter
		}
	}
	($numDupeKeys > 0) and verboseWarnPrint("Warning: $numDupeKeys duplicate keys were skipped in <$filename>.");
}

sub arrayOfNonKeyElements(\@$) {
    # Returns everything EXCEPT the key! This is because by default, when joining, you move the key to the FRONT of the line, and then do not print it again later on the line.
    my ($inputArrayPtr, $inputKey) = @_;
    ($isDebugging) && (($inputKey >= 1) or die "Whoa, the input key was LESS THAN ONE, which is impossible, since numbering for keys starts from 1! Not zero-indexing!!!");
    my @nonKeyElements = (); # the final array with everything BUT the key. Apparently doesn't matter much whether we pre-allocate it to the right size or not, speed-wise.
    for (my $i = 0; $i < scalar(@{$inputArrayPtr}); $i++) {
	if ($i != ($inputKey-1)) {
	    # remember that the input key is indexed from ONE and not ZERO!!!
	    push(@nonKeyElements, $inputArrayPtr->[$i]); # It's not a key, so add it to the array
	    #debugPrint("Adding $i (index $i is not equal to the input key index $inputKey)...\n");
	} else {
	    # Huh, this IS a key item, so don't include it!!!
	    #debugPrint("OMITTING $i (index $i is EXACTLY EQUAL to the input key index $inputKey. Remember that one of them counts from zero!)...\n");
	}
    }
    return (@nonKeyElements); # The subset of the inputArrayPtr that does NOT include the non-key elements!
}

sub joinedUpOutputLine($$$$$$$$) {
	my ($delim, $mainKey, $array1Ref, $k1col, $array2Ref, $k2col, $shouldNotMoveKey, $rev) = @_;

	if (!defined($mainKey)) { $mainKey = ""; } # if there is no main key (due to the input file having, for example, a TOTALLY BLANK line), we print a blank element here.

	if ($rev) {
		($k1col, $k2col) = ($k2col, $k1col); # Flip around which is "first" and which is "second"!
		($array1Ref, $array2Ref) = ($array2Ref, $array1Ref); # Flip around which is "first" and which is "second"!
	}
	if ($shouldNotMoveKey) {
		# do NOT move the key to the front of the line---this is a bit unusual! The key stays wherever it was on the line.
		return join($delim, @$array1Ref, @$array2Ref); # no newline!
	} else {
		# key gets moved to the front! -- like in unix join. This is the DEFAULT and UNIX-join-like way of doing it
		if (@{$array2Ref}) {
			return join($delim, $mainKey, arrayOfNonKeyElements(@{$array1Ref}, $k1col), arrayOfNonKeyElements(@{$array2Ref}, $k2col)); # no newline!
		} else {
			# array 2 was EMPTY
			return join($delim, $mainKey, arrayOfNonKeyElements(@{$array1Ref}, $k1col)); # no newline!
		}
	}
}

sub quitIfNonUnixLineEndings($$$) {
	my ($filename, $lineToCheck, $lineNum) = @_;
	($lineToCheck !~ m/\r/) or die "ERROR: Exiting! The file <$filename> appears to have either WINDOWS-STYLE line endings or MAC-STYLE line endings ( with an '\\r' character) (as seen on line $lineNum).\nThis behavior is often seen when files are saved by Excel. You will need to manually convert the line endings from Mac / Win format to UNIX. Search online for a way to do this. We cannot handle this character automatically at this point in time, and are QUITTING.\n";
	return 1;
}

sub is_line_array_too_weird_to_use(\@$$$) {
	my ($lineArrPtr, $lnum, $filename, $keyColIndexedFromOne) = @_;
	if (0 == scalar(@$lineArrPtr)) {
		maybeWarn($numBlankLines++, $MAX_BLANK_LINES_TO_REPORT, "on line $lnum in file <$filename> was blank. Skipping it.");
		return 1; # Disqualify this line, since it is TOTALLY EMPTY
	} elsif (scalar(@$lineArrPtr) < $keyColIndexedFromOne) { # The line was SHORTER than the demanded key column! $keycol is indexed from 1, not 0;
		maybeWarn($numMissingKeyCols++, $MAX_MISSING_KEY_COLS_TO_REPORT, "line $lnum was missing the key column in file <$filename>. (Key column: $keyColIndexedFromOne, Columns on line: " . scalar(@$lineArrPtr) . ").");
		# Disqualify this line, since it has no key!
		#$key = "";  # totally blank line maybe? Or at least, no key.
		#@valArr = ();
		return 1; # too weird
	} else {
		return 0; # not too weird
	}
}



sub handleMultiJoin($$$$$$) {
	my ($k1, $k2, $filenameArrPtr, $mergeType, $d1, $d2) = @_;
	
	my %datHash               = (); # this stores all the lines, and gets very large. Key = filename, value = hash with a second key = line key, value = array of data on that line
	my %longestLineInFileHash = (); # key = filename, value = how long the longest line in that file is
	my %keysHash              = (); # key = the keys seen in ALL files, value = (nothing useful)
	my %ocKeyHash             = (); # ORIGINAL CASE key hash. Only used if case-insensitive joining.
	
	($mergeType =~ m/^(${UNION_STR}|${INTERSECT_STR})$/i) or die "Programming error: multi-intersection type must be '$INTERSECT_STR' or '$UNION_STR'! But it was this: $mergeType";
	my $filenameHeaderDelim = "::"; # example:  "Filename1::headerCol1   Filename2::headerCol2"
	my $na = (defined($stringWhenNoMatch)) ? $stringWhenNoMatch : ""; # use a blank value if (global) $stringWhenNoMatch is not defined
	my %headHash = ();
	my $is_intersection     = ($mergeType =~ m/^${INTERSECT_STR}$/i);
	my $is_union            = ($mergeType =~     m/^${UNION_STR}$/i);
	my %numFilesWithKeyHash = (); # Counts the number of files that we saw this line in. Only used if this is an intersection and not a union
	my $numFilesOpened      = 0;
	my $numFilesExpected    = scalar(@$filenameArrPtr);
	my $totalLinesReadAcrossAllFiles = 0;
	foreach my $filename (@$filenameArrPtr) {
		my $numItemsOnFirstLine = undef;
		$numFilesOpened++; # ok, remember that we read a file
		#my %keysSeenAlreadyInThisFile = ();
		%{$datHash{$filename}} = (); # new hash value is an ARRAY for this
		if ($numHeaderLines == 0 and $includeFilenameInHeader) {
			@{$headHash{$filename}} = ( () ); # zero header lines, but in this case we'll initialize the header anyway
		} else {
			@{$headHash{$filename}} = (()x$numHeaderLines); # it's one array element per line
		}
		$longestLineInFileHash{$filename} = 0; # longest line is length 0 to start...
		#print STDERR "Handling file named $filename ...\n";
		($filename ne '-') or die "If you are multi-joining, you CANNOT read input from STDIN. Sorry.";
		(-e $filename) or die "Cannot read input file $filename.";
		my $fh = openSmartAndGetFilehandle($filename);
		my $lnum = 0;

		my $delim  = ($numFilesExpected == 2 && $numFilesOpened == 2 && defined($d2)) ? $d2 : $d1; # If there are EXACTLY TWO input files, then we allow delim1 and delim2 to be separately specified
		my $keycol = ($numFilesExpected == 2 && $numFilesOpened == 2 && defined($k2)) ? $k2 : $k1; # If there are EXACTLY TWO input files, then we allow key1 and key2 to be separately specified
		($keycol != 0 and defined($keycol)) or die "Keycol can't be 0 or undefined -- it's indexed with ONE as the first element.";
		(defined($delim))                   or die "delim can't be undefined.";
		foreach my $line (<$fh>) {
			$lnum++;
			$totalLinesReadAcrossAllFiles++;
			quitIfNonUnixLineEndings($filename, $line, $lnum);
			chomp($line);
			my @vals = split($delim, $line, $SPLIT_WITH_TRAILING_DELIMS); # split up the line
			if (is_line_array_too_weird_to_use(@vals, $lnum, $filename, $keycol)) {
				next; # line is too weird for us, maybe it's missing a key or something.
			}
			if (!defined($numItemsOnFirstLine)) { $numItemsOnFirstLine = scalar(@vals); }
			($numItemsOnFirstLine == scalar(@vals)) or maybeWarn($numWeirdLineLengths++, $MAX_WEIRD_LINE_LENGTHS_TO_REPORT, "Warning: the number of elements on each line of this file was NOT CONSTANT. The first line had $numItemsOnFirstLine columns, but line number $lnum in file <$filename> had " . scalar(@vals) . " instead. Continuing anyway.");

			my $key = $vals[($keycol-1)];  # get the correct key, since it might not be the first column, I guess!
			splice(@vals, ($keycol-1), 1); # <-- Delete the key column from the array! Splice MODIFIES the array---it REMOVES the key column, keep everything else!
			# ==========================================
			# Check for a certain (non-fatal) warning issues.
			($key !~ /\s/) or maybeWarn($numWhitespaceKeys++, $MAX_WHITESPACE_KEYS_TO_REPORT, "on line $lnum in file <$filename>, the key <$key> had *whitespace* in it. This is often unintentional, but is not necessarily a problem!");
			# ==========================================
			
			# Note: line length does NOT include the key as an element. So it can be zero!
			if ($longestLineInFileHash{$filename} < scalar(@vals)) { $longestLineInFileHash{$filename} = scalar(@vals); }
			my $this_is_a_header_line = ($lnum <= $numHeaderLines);
			if ($this_is_a_header_line) {
				@{${$headHash{$filename}}[$lnum-1]} = ($includeFilenameInHeader) ? map{"${filename}${filenameHeaderDelim}$_"}@vals : @vals; # It is ok if @valsy has zero elements.
			} else {
				if ($lnum == 1 and $numHeaderLines == 0 and $includeFilenameInHeader) {
					# Bonus weird thing if it's the first line
					# Include the filename in the 'header', even though there isn't a header line per se---we create a new one.
					@{${$headHash{$filename}}[$lnum-1]} = map{"${filename}"}@vals;
				}
				if (!$allowEmptyKey and $key eq "") {
					verboseWarnPrint("Warning: skipping an empty (blank) key on line $lnum of file <$filename>!");
				} elsif (exists($datHash{$filename}{$key})) {
					maybeWarn($numDupeKeysMultiJoin++, $MAX_DUPE_KEYS_TO_REPORT, "on line $lnum, we saw a duplicate of key <$key> (in file <$filename>). We are only keeping the FIRST instance of this key.");
				} else {
					#print "Added this key: $filename / $key ...\n";
					@{$datHash{$filename}{$key}} = @vals; # save this key with the value being the rest of the array
					$keysHash{$key} = 1;
				}
			}
		}
		closeSmartFilehandle($fh);
	}

	my $nHeaderLinesAccountingForFNH = ($includeFilenameInHeader and $numHeaderLines == 0) ? 1 : $numHeaderLines;  # basically, if include-filename-in-header is here, BUT we don't have any other header lines, then this value should be at least one!
	
	for (my $headerIndex = 0; $headerIndex < $nHeaderLinesAccountingForFNH; $headerIndex++) {
		my @head = ("KEY"); # the key is always named KEY no matter what
		for my $filename (@$filenameArrPtr) {
			my $thisHeadArrPtr = \@{${$headHash{$filename}}[$headerIndex]};
			my $numElemsToPad = $longestLineInFileHash{$filename} - scalar(@$thisHeadArrPtr);
			push(@head, @$thisHeadArrPtr, ($na)x$numElemsToPad);
		}
		print(join($outDelim, @head)."\n");
	}
	
	foreach my $k (sort(keys(%keysHash))) {
		# ========== See if the key is in EVERY SINGLE file, but only if we are computing an intersection! ======
		my $key_is_in_every_file = 0;
		if ($is_intersection) {
			my $numFilesWithKey = 0;
			foreach my $filename (@$filenameArrPtr) {
				if (exists($datHash{$filename}{$k})) { $numFilesWithKey++; } # see if this filename/key combination exists!
			}
			$key_is_in_every_file = ($numFilesWithKey == $numFilesOpened);
			#print "Skipping key <$k>: it was only in $numFilesWithKey files of $numFilesOpened, so we are skipping it for the intersection.\n";
		}
		my $key_is_in_enough_files = ($is_union || ($is_intersection && $key_is_in_every_file));
		if ($key_is_in_enough_files) {
			my @outLine = ($k); # output line. starts with just the key and nothing else
			foreach my $filename (@$filenameArrPtr) {
				if (exists($datHash{$filename}{$k})) {
					my $numElemsToPad = $longestLineInFileHash{$filename} - scalar(@{$datHash{$filename}{$k}});
					push(@outLine, @{$datHash{$filename}{$k}}, ($na)x$numElemsToPad);
				} else {
					push(@outLine, ($na)x$longestLineInFileHash{$filename});
				}
			}
			print join($outDelim, @outLine), "\n"; # <-- somehow this results in "uninitialized value" warning sometimes...
		}
	}
} # end of handleMultiJoin(...)
# ========================== MAIN PROGRAM HERE

#if (1) { #defined($multiJoinType)) {
	# Ok, we are doing MULTI-joining. Otherwise, just the regular (full-featured) two-file joining


if ($numFilesToJoin == 2) {
	# You can do a few different things if there are EXACTLY two files!
	#print "join type: $multiJoinType\n";
	#print "match str: $stringWhenNoMatch\n";
	handleMultiJoin($keyCol1, $keyCol2, \@files, $multiJoinType, $delim1, $delim2);
} else {
	#(not $shouldReverse) or quitWithUsageError("For multi-joining, reversal of output order is not supported. Remove --rev from the command line!");
	(not $shouldNegate) or quitWithUsageError("For multi-joining, negation is not supported. Remove --neg / -v from the command line!");
	#(not $preserveKeyOrder) or quitWithUsageError("For multi-joining, preserving key order is not supported. Remove --no-reorder-key (--nrk) from the command line!");
	# 3+ files, so we really are using the 'multi-join' functionality
	if (!defined($multiJoinType)) { quitWithUsageError("Since you specified three or more files to join, you MUST also specify an intersection type! Use --multi=union or --multi=intersect."); }
	elsif ($multiJoinType =~ /^i/) { handleMultiJoin($keyCol1, undef, \@files, 'intersect', $delim1, undef); }
	elsif ($multiJoinType =~ /^u/) { handleMultiJoin($keyCol1, undef, \@files, 'union'    , $delim1, undef); }
	else { die "Invalid multi-join type."; }
}
($numDupeKeysMultiJoin > 0) and verboseWarnPrint("Warning: $numDupeKeysMultiJoin duplicate keys were skipped in the multi-joining.");
#}

# else {
# 	my %hash2 = ();
# 	my %originalCaseHash = (); # Hash: key = UPPER CASE version of key, value = ORIGINAL version of key
# 	my $originalCaseHashRef = ($shouldIgnoreCase) ? \%originalCaseHash : undef; # UNDEFINED if we aren't ignoring case
# 	readIntoHash($file2, $delim2, $keyCol2, \%hash2, $originalCaseHashRef);
# 	debugPrint("Read in this many keys: " . scalar(keys(%hash2)) . " from secondary file.\n");
# 	my $lineNumPrimary     = 0;
# 	my $primaryFH          = openSmartAndGetFilehandle($file1);
# 	my $prevLineCount1     = undef;
# 	my $prevLineCount2     = undef;
# 	foreach my $line (<$primaryFH>) {
# 		if ($lineNumPrimary % 2500 == 0) {
# 			verboseUpdatePrint("Line $lineNumPrimary...");
# 		}
# 		$lineNumPrimary++; # Start it at ONE during the first iteration of the loop! (Was initialized to zero before!)
# 		quitIfNonUnixLineEndings($file1, $line, $lineNumPrimary);
# 		#$line =~ s/\r\n?/\n/g; # Actually it TOTALLY FAILS on mac line endings! You cannot loop over them. Should work on PC line endings though. Turn PC-style \r\n, or Mac-style just-plain-\r into UNIX \n
# 		chomp($line); # Chomp each line of line endings no matter what. Even the header line!
# 		if ($lineNumPrimary <= $numHeaderLines) { # This is still a HEADER line, also: lineNumPrimary starts at 1, so this should be '<=' and not '<' to work properly!
# 			verboseWarnPrint("Note: directly printing $lineNumPrimary of $numHeaderLines header line(s) from file 1 (\"$file1\")...");
# 			print STDOUT $line . "\n"; # Print the input line, making sure to use a '\n' as the ending.
# 			next;	# <-- skip to next iteration of loop!
# 		}
# 		#if(/\S/) { ## if there's some content that's non-spaces-only
# 		my @sp1 = split($delim1, $line, $SPLIT_WITH_TRAILING_DELIMS); # split-up line
# 		(!defined($prevLineCount1) or $prevLineCount1==scalar(@sp1)) or maybeWarn($numWeirdLengths++, $MAX_WEIRD_LINE_LENGTHS_TO_REPORT, "the number of elements in file 1 ($file1) is not constant. Line $lineNumPrimary had this many elements: " . scalar(@sp1) . " (previous line had $prevLineCount1)");
# 		$prevLineCount1 = scalar(@sp1);

# 		my $thisKey;
# 		if (scalar(@sp1) == 0) {
# 			$thisKey = undef;
# 			maybeWarn($numBlankLines++, $MAX_BLANK_LINES_TO_REPORT, "line $lineNumPrimary was blank, so it had no key.");
# 		} elsif (($keyCol1-1) >= scalar(@sp1)) {
# 			$thisKey = undef;
# 			maybeWarn($numMissingKeyCols++, $MAX_MISSING_KEY_COLS_TO_REPORT, "line $lineNumPrimary was missing the key column. (Key column: $keyCol1, Columns on line: " . scalar(@sp1) . ").");
# 		} else {
# 			$thisKey = $sp1[ ($keyCol1-1) ]; # index from ZERO here, that's why we subtract 1 from the key column
# 			($thisKey !~ /\s/) or maybeWarn($numWhitespaceKeys++, $MAX_WHITESPACE_KEYS_TO_REPORT, "on line $lineNumPrimary in file <$file1>, the key <$thisKey> had *whitespace* in it. This is often unintentional, but is not necessarily a problem!");
# 		}
		
# 		my @sp2;	# matching split-up line
# 		if (!defined($thisKey)) {
# 			@sp2 = (); # undefined key can NEVER match anything
# 		} elsif ($shouldIgnoreCase) {
# 			my $keyInOrigCase = $originalCaseHash{uc($thisKey)}; # mutate the key so that it's in the SAME CASE as it was in the key we added
# 			#print "Found key \"$keyInOrigCase\" from upper-case " . uc($thisKey) . "...\n";
# 			if (defined($hash2{$thisKey})) {
# 				@sp2 = @{$hash2{$thisKey}}; # () <-- empty list/array is the result of "didn't find anything"
# 			} else {
# 				@sp2 = (defined($keyInOrigCase) and defined($hash2{$keyInOrigCase})) ? @{$hash2{$keyInOrigCase}} : (); # () <-- empty list/array is the result of "didn't find anything"
# 			}
# 		} else {
# 			@sp2 = (defined($hash2{$thisKey})) ? @{$hash2{$thisKey}} : (); # () <-- empty list/array is the result of "didn't find anything"
# 		}
		
# 		if (@sp2) {
# 			# Got a match for the key in question!
# 			if (defined($prevLineCount2) and $prevLineCount2 != scalar(@sp2)) {
# 				($numWeirdLengths < $MAX_WEIRD_LINE_LENGTHS_TO_REPORT) and verboseWarnPrint("Warning: the number of elements in file 2 ($file2) is not constant. Got a line with this many elements: " . scalar(@sp2) . " (previous line had $prevLineCount2)");
# 				($numWeirdLengths == $MAX_WEIRD_LINE_LENGTHS_TO_REPORT) and verboseWarnPrint("Warning: suppressing any further non-constant elements-per-line warnings.");
# 				$numWeirdLengths++;
# 			}
# 			$prevLineCount2 = scalar(@sp2);
			
# 			if ($shouldNegate) {
# 				# Since we are NEGATING this, don't print the match when it's found (only when it isn't...)
# 			} else {
# 				# Great, the OTHER file had a valid entry for this key as well! So print it... UNLESS we are negating.
# 				print STDOUT joinedUpOutputLine($outDelim, $thisKey, \@sp1, $keyCol1, \@sp2, $keyCol2, $preserveKeyOrder, $shouldReverse) . "\n";
# 			}
# 		} else {
# 			# Ok, there was NO MATCH for this key!
# 			defined($thisKey) and debugPrint("WARNING: Hash2 didn't have the key $thisKey\n");
# 			if ($shouldNegate) {
# 				# We didn't find a match for this key, but because we are NEGATING the output, we'll print this line anyway
# 				print STDOUT joinedUpOutputLine($outDelim, $thisKey, \@sp1, $keyCol1, \@sp2, $keyCol2, $preserveKeyOrder, $shouldReverse) . "\n";
# 			} else {
# 				if (defined($stringWhenNoMatch)) {
# 					# We print the line ANYWAY, because the user specified an outer join, with the "-o SOMETHING" option.
# 					my $suffixWhenNoMatch = (length($stringWhenNoMatch)>0) ? "${outDelim}${stringWhenNoMatch}" : "$stringWhenNoMatch"; # handle zero-length -ob SPECIALLY
# 					print STDOUT joinedUpOutputLine($outDelim, $thisKey, \@sp1, $keyCol1, \@sp2, $keyCol2, $preserveKeyOrder, $shouldReverse) . $suffixWhenNoMatch . "\n";
# 				} else {
# 					# Omit the line entirely, since there was no match in the secondary file.
# 				}
# 			}
# 		}
# 		#print "$line\n";
# 	}
# 	if ($file1 ne '-') { close($primaryFH); } # close the file we opened in 'openSmartAndGetFilehandle'
# }


exit(0); # looks like we were successful


################# END MAIN #############################

__DATA__
syntax: join.pl [OPTIONS] LOOKUP_FILE  HUGE_DICTIONARY_FILE

join.pl goes through each line/key in the LOOKUP_FILE, and finds the *first* matching
key in the DICTIONARY_FILE. The data from those corresponding rows is then
printed out. It does not handle cross-products.

Unlike the UNIX "join", join.pl does NOT require sorted keys.

 * Note that join.pl reads the ENTIRE contents of the second file into memory! It may be unsuitable for joining very large (> 1000 MB) files.

DESCRIPTION:

This script takes two tables, contained in delimited files, as input and
produces a new table that is a join of FILE1 and FILE2.

By default, files are assumed to be tab-delimited with the keys in the first column.
(See the options to change these defaults.)

If FILE1 contains the tuple (VOWELS, A, O, A) and FILE2 contains the
tuple (VOWELS, I, U, U) then the joined output will be (VOWELS, A, O, A, I, U, U)

CAVEATS:

Every line of the LOOKUP_FILE is processed in the
order that it appears in the file.

The DICTIONARY_FILE is only for handling join operations.

If the DICTIONARY_FILE contains several lines with the same key,
only the *LAST* key read will actually ever be used.

Because of this, join.pl does NOT exactly duplicate the function of
GNU "join"--in particular it does not output the cross-product
in multiple-key situations.

*** NOTE: If you are trying to merge two files, or you are joining ***
*** multiple times with multiple files, try "join_multi.pl" .      ***

OPTIONS are:

-1 COLUMN: Include column COL from FILE1 as part of the key (default: 1).
        Only supports ONE key field, unlike unix join. Indexed starting at 1.

-2 COLUMN: Include column COL from FILE2 as part of the key (default: 1).
        Only supports ONE key field, unlike unix join. Indexed starting at 1.

-o TEXT:  Do a left outer join.  If a key in FILE1 is not in FILE2, then the
          tuple from FILE1 is printed along with the FILLER TEXT in place of
          a tuple from FILE2 (by default these tuples are not reported in the
          result). (See 'examples' section for usage.)
          Example:  join -o "NO_match_in_file2" FILE1.txt FILE2.txt > OUTPUT.txt

--ob: Same as -o ''---report blank entries for non-matching output.

-h INT: Number of header lines to print verbatim (without joining) from FILE1. (default: 0)
  * Note the "--fnh" option if you want the header lines to be meaningful across files with
  duplicate header lines.

For multi-joining only:
  --fnh or --filename-in-header: Print the filename in the header. Very useful! Example:
        KEY        file1::col1.txt   file2::col1.txt     file2::col2.txt

  --multi=union:  Run a multi-file join. Different engine and behaviors from 2-files-only joining. Beware!

  --multi=intersect: Run a multi-file join and ONLY report the intersection.
  
-neg: Negate output -- print keys that are in FILE1 but not in FILE2.
        These keys are the same ones that would be left out of the join,
        or those that would have a FILL tuple in a left outer join
        Cannot specify both this AND ALSO -ob or -o.

-t DELIM or -d DELIM or --delim=DELIM:
        Set the input delimiters for both FILE1 and FILE2 to DELIM (default: tab)
        Equivalent to setting both --d1 and --d2.

--d1=DELIM: Set the input delimiter for FILE1 to DELIM (default: tab).

--d2=DELIM: Set the input delimiter for FILE2 to DELIM (default: tab).

--do=DELIM: Set the OUTPUT delimiter to DELIM. (default: same as input delim)

--allow-empty-key or --eok: (Default: do not allow it): Whether to allow an EMPTY key / blank key as valid.
  Note: even when the empty key is NOT allowed for matching, if we do an outer join or
  negation, we will still print items from FILE1 where the key was blank.

-i or --ignore-case: (Case-insensitive join)

-q or --quiet : No verbose output. May hide some useful warning messages!

Example:

join.pl -1 1 -2 2 file1--key_in_first_col.txt  file2--key_in_second_col.compressed.gz > join.output.txt
  Print lines from file1 that are ALSO in file2, and append the data from file2 in the output.
  This is the most standard-plain-vanilla join, and should be similar to the unix "join" results.

join.pl -o "NO_MATCH_HERE_I_SEE" -1 4 -2 1 file_with_key_in_fourth_col.compressed.bz2  file2.gz > join.with.unmatched.rows.txt
  Also print the un-matching lines from the first file (lines with no match will say "NO_MATCH_HERE_I_SEE")

join.pl --multi=union   file1.txt   file2.txt   file3.txt
  Join MORE than two files. Has different behaviors from joining exactly two files. Some options do not work
  with multi-file joining (example: --neg does not work).
  Be aware of --fnh (filename in header), which can help a lot when multi-joining files with otherwise-identical keys!

cat myfile.txt | join.pl - b.txt | less -S
  Read from STDIN (use a '-' instead of a filename!), and pipe into the program "less".

join.pl --no-reorder-key a.txt b.txt > a_and_b.txt
join.pl --no-reorder-key a_and_b.txt c.txt > a_and_b_and_c.txt
  Since we are using --no-reorder-key, it makes it easier to join multiple files sometimes, since the order of columns
  does not keep moving around. This is only of interest if your key column is NOT the very first one already!

Detailed example:

If you have the following two files:

File1 (tab-delimited)       <-- FIRST FILE
    AAA   avar    aard
    ZZZ   zebra                     <-- Note the differing number of items per line!
    BBB   beta    bead    been          This *usually* indicates a problem in your input data.
    MMM   man     most                  Alex wrote "table-no-ragged.py" to pad any blank spaces,
                                        so you can use that if your file has "ragged" edges.

File2 (tab-delimited)       <-- SECOND FILE
    AAA   111
    BBB   222
    CCC   333

Then the result of a regular join.pl invocation...
   join.pl File1 File2
...is:
    AAA   avar    aard    111             <-- Note: 4 columns in all
    BBB   beta    bead    been    222     <-- Note: 5 columns in all

The result of an outer join (i.e., use File1 as the "master" file)...
   join.pl -o "NONE!" File1 File2
Results in:
    AAA    avar     aard      111
    ZZZ    zebra    NONE!
    BBB    beta     bead      been      222
    MMM    man      mouse     NONE!

Note that if you switch the order of File1 and File2 for an outer join...
...you get a different result (the first file specifies the keys)!

'--fnh' is "filename in header," which is a convenient way of labeling all of the
columns in the (common) case where many files have identical column headers.

join.pl --fnh -o "NOPE!" File2.txt File1.txt
  Results in:
    KEY    File1.txt File2.txt
    AAA    111       avar      aard
    BBB    222       beta      bead       been
    CCC    333       NOPE!

----------
Note that UNIX join will behave differently from
join.pl on the input FILE1 and FILE2 given below:

FILE1: (tab-delimited)
Alpha   1   2
Alpha   3   4

FILE2: (tab-delimited)
Alpha   a   first
Alpha   b   middle
Alpha   c   last

----------



  # -i / ignore case is not working
  # -v / --neg is not working
