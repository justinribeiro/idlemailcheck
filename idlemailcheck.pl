#!/usr/bin/env perl
#######################################
#
#  idlemailcheck - IMAP IDLE mail check with Snarl notification
# 
#  Copyright (C) Justin Ribeiro <justin@justinribeiro.com>
#  Project Page - http://www.justinribeiro.com/  
# 	  
#   This program is free software; you can redistribute it and/or
#   modify it under the terms of the GNU General Public License
#   as published by the Free Software Foundation; either version 2 of
#   the License or (at your option) any later version.
#   
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied warranty
#   of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#   
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
#   USA
#
#   11/19/2010
#	JDR - "I work again!" Release 0.0.3
#		- FIX: now based on Mail::IMAPClient v3.25
#		- UPD: based on new idle_data() and sample from http://cpansearch.perl.org/src/PLOBBES/Mail-IMAPClient-3.25/examples/idle.pl
#
#   12/16/2009
#	JDR - "I'm always connected!" Release 0.0.2
#		- FIX: 30 minute disconnect issue
#		- UPD: KeepAlive enabled for unstable connections
#
#   08/28/2009
#	JDR - Initial Concept Release 0.0.1
#
#  The script logs into an IMAP server of your  choice (which must support 
#  the IDLE command), sits at IDLE until the mail server has a new email, and 
#  then returns a Snarl notification when new mail arrives.
#
#  This connect portion of the script is based on the Gmail connect script at Perl Monks 
#  that was written by polettix and refined by markov: http://www.perlmonks.org/?node_id=649742
#
#  Requirements
#  1. Snarl for Windows (http://www.fullphat.net/)
#  2. Win32::Snarl
#  3. IO::Socket::SSL
#  4. Mail::IMAPClient
#
#  You must set the variables below for your specific IMAP server. If you want the icon
#  to appear, make sure you update to the full path as in the example below.
#
#  Tested with:
#
#  * Gmail 
#  * Google Apps for Domain
#
#  Feel free to make changes and additions;  I'm open to suggestions, fixes, and just
#  plain better ways to do things.
#  
#  Released under the GPL License.  Use at your own risk. 
#
#######################################

use warnings;
use strict;
use Mail::IMAPClient;
use IO::Socket::SSL;
use Win32::Snarl;

#### SETUP - YOU MUST SET THE FOLLOWING OR NOTHING WILL WORK
my $IMAP_server = "imap.gmail.com";
my $IMAP_port = "993";
my $IMAP_user = "user\@gmail.com";
my $IMAP_password = "yourpassword";
my $SNARL_disptime = 7; # number of seconds to display snarls alerts

# path to icon
# icon from Jonas Rask Design http://jonasraskdesign.com/ (free for personal use)
# if you use a differnt icon, it must be 128x128 png
my $use_icon = "C:\\cygwin\\home\\justin\\scripts\\stamp.png";

#### EDITING BELOW AT OWN RISK

use constant {
    FOLDER  => "INBOX",
    MAXIDLE => 300,
};

$| = 1;    # set autoflush
my $DEBUG   = 0;              # GLOBAL set by process_options()
my $QUIT    = 0;

# JDR: from the example
# main program
main();

sub main {

# Connect to the IMAP server via SSL
	my $socket = IO::Socket::SSL->new(
	   PeerAddr => $IMAP_server,
	   PeerPort => $IMAP_port,
	  )
	  or die "socket(): $@";
	
	# Build up a client attached to the SSL socket.
	# Login is automatic as usual when we provide User and Password
	my $client = Mail::IMAPClient->new(
	   Socket   => $socket,
	   KeepAlive => 'true',
	   User     => $IMAP_user,
	   Password => $IMAP_password,
	  )
	  or die "new(): $@";
	
	# we set Uid to false so that we can use the message sequence number to email information
	$client->Uid(0);
	
	if ($client->IsAuthenticated()) 
	{
	   Win32::Snarl::ShowMessage('Gmail Authenticated', 'You are now logged into Gmail.', $SNARL_disptime, $use_icon);	   
	}
	
	# need these for later
	my $noidle = 0;
	my $last = 0;
	my $buf;
	my $bytes_read;
	my $my_ID;
	my $msg_count;

    my ( $folder, $chkseen, $tag ) = ( "INBOX", 1, undef );

    $client->select($folder) or die("$Prog: error: select '$folder': $@\n");

    $SIG{'INT'} = \&sigint_handler;

    until ($QUIT) {
        unless ( $client->IsConnected ) {
            Win32::Snarl::ShowMessage("Error. Reconnecting...", "$@", $SNARL_disptime, $use_icon) if $client->LastError;
            $client->connect or last;
            $client->select($folder) or last;
            $tag = undef;
        }

        my $ret;

        # idle for X seconds unless data was returned by done
        unless ($ret) {
            $tag ||= $client->idle
              or die("$Prog: error: idle: $@\n");

            $ret = $client->idle_data("300") or last;

            # connection can go stale so we exit/re-enter of idle state
            # - RFC 2177 mentions 29m but firewalls may be more strict
            unless (@$ret) {
                $tag = undef;

                # restarted lost connections on next iteration
                $ret = $client->done or next;
            }
        }

        local ( $1, $2, $3 );
        foreach my $resp (@$ret) {
            $resp =~ s/\015?\012$//;
			if ( $resp =~ /^\*\s+(\d+)\s+(EXISTS)\b/ ) {
				$resp =~ s/\D//g;
				
				# JDR: we do this, otherwise we can't talk to the server to get the headers for the UID
				my $exitmeforasecond = $client->done;
				
				#check the unseen_count; this is a precaution, because for some reason Gmail at times responds with a new message notifcation, but's it's really not.
				$msg_count = $client->unseen_count||0;       	
				
				if ($msg_count > 0)
				{
					# Email Data: Sender's address 
					my $from = $client->get_header($resp, "From");
					$from =~ s/<[^>]*>//g; #strip the email, only display the sender's name
					
					# Email Data: Subject
					my $subject = $client->get_header($resp, "Subject");
								
					# Send event to Snarl
					my $winNM = Win32::Snarl::ShowMessage($from, $subject, $SNARL_disptime, $use_icon);
					
					# JDR: fire back up the idle
					my $restartmeforasecond = $client->idle;
				}
			}
			
        }
    }

    my $rc = 0;
    if ($@) {
        if ($QUIT) {
			Win32::Snarl::ShowMessage("idelmailcheck error", "caught signal, exiting script", $SNARL_disptime, $use_icon);
			$client->logout;
        }
        else {
            $rc = 1;
        }
        Win32::Snarl::ShowMessage("IMAP Error", "$@", $SNARL_disptime, $use_icon) if ( !$QUIT || $DEBUG );
    }
    exit($rc);
}

sub sigint_handler {
    $QUIT = 1;
}
