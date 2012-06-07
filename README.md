idlemailcheck
=============

IMAP IDLE mail check with Snarl notification for Perl

What is this?
=============
A proof of concept script that uses Mail::IMAPClient IDLE support, a Perl socket, and Snarl to display new mail notifications to the user without polling the mail server on a defined interval.

Should I expect perfection?
=============
No. This is an example that has a few bugs, but shows what can be done with Mail::IMAPClient IDLE command. 