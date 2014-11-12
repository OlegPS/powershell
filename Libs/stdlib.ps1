$SCRIPT:__stdlib__ = $True;

$_stdlib_Notify_From = "me@mysite.local";
$_stdlib_Notify_To = "me@mysite.local";
$_stdlib_Notify_Subject = "New exception";
$_stdlib_Notify_SMTPServer = "smtp.mysite.local";

$ErrorActionPreference = "Stop";
$OutputEncoding = New-Object -Typename System.Text.UTF8Encoding;

# --------- Include MySQL library ---------
if (!$__mysql__){. ((Split-Path -Parent -Path $MyInvocation.MyCommand.Definition).ToString()+"\mysql.ps1")}
# ----- mysql library is now included -----

function stdlib_Notify {
	[cmdletbinding(defaultparametersetname="Message")]
	param(
		[parameter(mandatory=$true, position=0)]$Message,
		[parameter(mandatory=$false, position=1)][string]$Subject,
		[parameter(mandatory=$false, position=2)][string]$From,
		[parameter(mandatory=$false, position=3)][string]$To,
		[parameter(mandatory=$false)][switch]$AttachDump,
		[parameter(mandatory=$false)][switch]$WriteToDB
	) 
	if (!$subject) {$subject = $_stdlib_Notify_Subject;}
	if (!$from) {$from = $_stdlib_Notify_From;}
	if (!$to) {$to = $_stdlib_Notify_To;}
	if (!$AttachDump) {$AttachDump = $False;}
	else {echo "" > $env:TEMP\stdlib_Notify_Dump.txt;}
	if (!$WriteToDB) {$WriteToDB = $False;}

	[string]$_stdlib_Notify_Body = '<meta http-equiv="content-type" content="text/html; charset=UTF-8">';
	
	if ($message.GetType().Name -eq "ErrorRecord") {
		$_stdlib_Notify_Body += "<pre><b>DATE:</b> $(Get-Date)<br />";
	    $_stdlib_Notify_Body += $message.Exception 
		while ($_stdlib_Notify_Body -match "`r`n`r`n") {
			$_stdlib_Notify_Body = $_stdlib_Notify_Body -replace "`r`n`r`n","`r`n"
		}
		$_stdlib_Notify_Body += "`nAt line:" + [string]$message.InvocationInfo.ScriptLineNumber + ":" + [string]$message.InvocationInfo.OffsetInLine + " " + $([string]$message.InvocationInfo.Line -replace "\s{2,999}"," ") + "</pre><br />";
	} else {
		$_stdlib_Notify_Body += "`n<pre><b>MESSAGE:</b> " + $($message -replace '#(\S*)', '<a href="#anchor_$1">$$$1</a>');
		$_stdlib_Notify_Body += "`n<pre><b>DATE:</b> $(Get-Date)";
		$_stdlib_Notify_Body += "`n<b>ARGUMENTS:</b> " + [Environment]::GetCommandLineArgs() + "</pre>";;
	}
	$_stdlib_CallStack = Get-PSCallStack;
	$_stdlib_Notify_Body += $("`n<pre><b>CALLSTACK: </b><u>"+(($_stdlib_CallStack|%{echo $($_.Location)}) -join "</u> from: <u>").ToLower()+"</u></pre>`n");

	# List all variables
	for ($i = 1; $i -lt $_stdlib_CallStack.Count; $i++) {
		$_stdlib_Notify_Body += "`n<hr /><table>";
		$_stdlib_Notify_Body += $("`n<tr><td colspan=`"2`"><h5>Function '"+$_stdlib_CallStack[$i].Command+"' called from "+$_stdlib_CallStack[$i].Location+" with arguments: "+$_stdlib_CallStack[$i].Arguments+"</h5></td></tr>`n");
		if ($AttachDump -and !$WriteToDB) {$("`n`nFunction '"+$_stdlib_CallStack[$i].Command+"' called from "+$_stdlib_CallStack[$i].Location+" with arguments: "+$_stdlib_CallStack[$i].Arguments+"`n")>>$env:TEMP\stdlib_Notify_Dump.txt;}
		Try {
			$(gv -Scope $i |%{
				if ($_.Name -ne "Error" -and $_.Name -ne "foreach") {
					$_stdlib_Notify_Body += $(
					"<tr><td><b><pre>"+
					'<a name="anchor_'+$_.Name+'"></a>'+$_.Name+
					"</pre></b></td><td><pre>"+
					$(
						if ($_.Value.Length -gt 4096 -and $_.Value -isnot [array]) {
							($_.Value.Substring(0,4096)+"...")
						} elseif ($_.Value.Count -gt 20) {
							"<i>Collection of the " + $_.Value.GetType().Name + " contains " + $_.Value.Count + " elements, like " + $_.Value[0] + "</i>"
						} else {
							$_.Value
						}
					)+
					"</pre></td></tr>`n")
				};
				if ($AttachDump -and !$WriteToDB) {$_|fc -Force -Depth 5|Out-String -Width 4096 >>$env:TEMP\stdlib_Notify_Dump.txt;} 
			});
			$_stdlib_Notify_Body += "</table>";
		}
		Catch {
			$_stdlib_Notify_Body += "</table>";
			$_stdlib_Notify_Body += "<center>--- listing was aborted ---<br />" + $_ + "</center>";
			Continue;
		}
	}

	Try {
		if ($AttachDump -and !$WriteToDB) {
			Send-MailMessage -BodyAsHTML "$_stdlib_Notify_Body" -From $from -SmtpServer $_stdlib_Notify_SMTPServer -Subject $subject -To $to -Encoding $OutputEncoding -Attachments $env:TEMP\stdlib_Notify_Dump.txt;
		} elseif (!$AttachDump -and !$WriteToDB) {
			Send-MailMessage -BodyAsHTML "$_stdlib_Notify_Body" -From $from -SmtpServer $_stdlib_Notify_SMTPServer -Subject $subject -To $to -Encoding $OutputEncoding;
		} else {
			# Create table
			$_stdlib_sql = "CREATE TABLE IF NOT EXISTS ``stdlib_Notify`` (
				``id`` INT(11) UNSIGNED NOT NULL AUTO_INCREMENT,
				``Subject`` TEXT NULL,
				``To`` TEXT NULL,
				``From`` TEXT NULL,
				``Date`` DATETIME NULL DEFAULT NULL,
				``Body`` TEXT NULL,
				PRIMARY KEY (``id``)
				)
				COLLATE='utf8_general_ci'
				ENGINE=InnoDB;";
			mysql_ExecSQL "delayed_notifications" $_stdlib_sql;
			# Add message to DB
			$_stdlib_Date = mysql_ConvertDate $(Get-Date);
			$_stdlib_Body = mysql_Escape $("<h3>" + $Message + "</h3>" + $($_stdlib_Notify_Body -replace '<hr[ /]*>'));
			$_stdlib_sql = "INSERT INTO ``stdlib_Notify`` (``Subject``, ``To``, ``From``, ``Date``, ``Body``) VALUES ('$Subject', '$To', '$From', '$_stdlib_Date', '$_stdlib_Body')";
			mysql_ExecSQL "delayed_notifications" $_stdlib_sql;
		}
	}
	Catch {
	$_stdlib_Notify_Body > $env:TEMP\stdlib_Notify_Dump.txt;
	write-host $("`nUSER $(whoami) CANNOT NOTIFY ABOUT:") -fore red;
	write-host $($($_stdlib_Notify_Body.Substring(0, $_stdlib_Notify_Body.IndexOf("<hr />")) -replace '<br[ /]*>', "`n" -replace '</td><td>', ' = ' -replace '<.*?>') + "...`n`n");
	}
}
