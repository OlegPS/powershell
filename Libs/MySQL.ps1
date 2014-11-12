$SCRIPT:__mysql__ = $True;

# --------- Include stdlib library ---------
if (!$__stdlib__){. ((Split-Path -Parent -Path $MyInvocation.MyCommand.Definition).ToString()+"\stdlib.ps1")}
trap {stdlib_Notify $_;}
# ----- stdlib library is now included -----

$mysql_connector = "C:\Program Files (x86)\MySQL\MySQL Connector Net 6.7.4\Assemblies\v2.0\MySQL.Data.dll"; # Path to MySQL.Data.dll
$mysql_server = "mysql.local";
$mysql_user = "username";
$mysql_password = "password";

function mysql_ConvertDate {
	[cmdletbinding(defaultparametersetname="DateTimeString")]
	param(
		[parameter(mandatory=$false, position=0)]$DateTimeString
	)
	if (!$DateTimeString) {return "0000-00-00 00:00:00";}
	return "{0:yyyy-MM-dd HH:mm:ss}" -f $DateTimeString;
}

function mysql_Escape {
	[cmdletbinding(defaultparametersetname="Text")]
	param(
		[parameter(mandatory=$false, position=0)]$Text
	)
	$Text = $Text -replace '\\','\\';
	$Text = $Text -replace "'","\'";
	return $Text;
}

function mysql_ExecSQL {
	[cmdletbinding(defaultparametersetname="DBName,SQL")]
	param(
		[parameter(mandatory=$true, position=0)][string]$DBName, 
		[parameter(mandatory=$true, position=1)][string]$SQL,
		[parameter(mandatory=$false, position=3)][switch]$EmptyToNull = $True
	)
	
	# Convert empty values to NULL
	if ($EmptyToNull) {
		$SQL = $SQL -replace "([^\\])''",'$1NULL' -replace '([^\\])""','$1NULL';
	}
	[void][System.Reflection.Assembly]::LoadFrom($mysql_connector);
	$connectionString = "server=$mysql_server;database=$DBName;uid=$mysql_user;pwd=$mysql_password;Convert Zero Datetime=True";
	$connection = New-Object MySql.Data.MySqlClient.MySqlConnection;
	$connection.ConnectionString = $connectionString;
	$connection.Open();
	$command = New-Object MySql.Data.MySqlClient.MySqlCommand($SQL, $connection);
	$dataAdapter = New-Object MySql.Data.MySqlClient.MySqlDataAdapter($command);
	$dataSet = New-Object System.Data.DataSet;
	try {
		$recordCount = $dataAdapter.Fill($dataSet, "sample_data");
	}
	catch {
		stdlib_Notify $_;
		throw $_;
	}
	$connection.Close();
	return 	$dataSet.Tables["sample_data"];
}
