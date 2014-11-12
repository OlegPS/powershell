##############
# PARAMETERS #
##############
[CmdletBinding()]
Param(
	[string]$Path, # Path to dump NTFS ACL
	[string]$DBName, # Write result to DB
	[string]$Identer, # Character used for idents, default <TAB>
	[string]$Depth, # Subfolders depth to check, default 99
	[switch]$Csv, # Print result as CSV
	[switch]$WithFiles, # Also collect ACL for files
	[switch]$ShowSDDL, # Print SDDL info
	[switch]$IncludeInherited, # Print inherited permissions
	[switch]$IncludeOwner, # Print owner name
	[switch]$Userlist, # Print all users membership for each group, including indirect members
	[switch]$UserlistTree, # Print all groups and users having access in a tree-like structure
	[switch]$IncludeListPermissions, # Print LIST permissions
	[switch]$IncludeTechnicalPermissions, # Print technical permissions listed in $WellKnownIdentityReferences
	[switch]$Single, # Do not walk into subfolders
	[switch]$GroupnamesOnly, # Print only group names
	[switch]$SkipUnusual, # Do not print unusual permissions
	[switch]$SkipInheritedOnDirectlyAssigned # Do not print inherited permissions on folders with directly assigned permissions
)

#################
# CONFIGURATION #
#################
# ActiveRoles Server address
$ARSServer = "ars.local";

# Technical permissions that should be skipped normally
$WellKnownIdentityReferences = @(
	"CREATOR OWNER",
	"NT AUTHORITY\SYSTEM",
	"BUILTIN\Administrators"
);

$newLine = "`r`n";

# Default database and table names
# Database connection uses MySQL library
$db_name = $DBName;
$db_tbl_paths = "fs_paths"; # Store paths here
$db_tbl_permissions = "fs_permissions"; # Store permissions here

# Default ident symbol for output
if (!$Identer) {$Identer="`t"};

# Default nested folder level
if (!$Depth) {$Depth=99};


###########
# OBJECTS #
###########
$_md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider;
$_utf8 = New-Object -TypeName System.Text.UTF8Encoding;
$_folderStack = New-Object System.Collections.Stack;

#############
# FUNCTIONS #
#############
# Gets string hash
function Get-Hash([String] $String,$HashName = "MD5") { 
	$StringBuilder = New-Object System.Text.StringBuilder;
	[System.Security.Cryptography.HashAlgorithm]::Create($HashName).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($String.ToLower()))|%{[Void]$StringBuilder.Append($_.ToString("x2"))};
	return $StringBuilder.ToString();
}

# Loads library
function LoadLibrary([string]$LibraryName) {
	if ($LibraryName -match '\.ps1$') {
		$LibraryName = $LibraryName -replace '\.ps1$','';
	}
	if ((gv ('__'+$LibraryName+'__') -ErrorAction SilentlyContinue)) {
		return;
	}
	$LibraryPath = $LibraryName + ".ps1";
	$my_path = (pwd).path + "\";
	while ($my_path -match '\\') {
		$my_path = $my_path -replace('(.*)\\.*','$1');
		$lib_path = cmd /c "cd $my_path\ && dir /a-d /b /s $LibraryPath 2> nul";
		if ($lib_path -match "$LibraryPath$") { break; }
	}
	foreach ($library in ($lib_path|sort -Property length)) {
		if ((cat $library|select -first 1) -like ('$SCRIPT:__'+$LibraryName+'__*')) {
			. "$library";
			return;
		}
	}
	Throw "Cannot load library $LibraryName";
}

# Recursively gets group members via ARS
function Get-GroupMembers([array]$groupname, $iteration)
{
	$ident = "$identer" + "$identer" * $iteration;
	
	if ($groupname.count -gt 1) {
		[array]$groups = get-qadobject -SizeLimit 0 $groupname -type group;
	} elseif ($groupname.count -eq 1) {
		[array]$groups = $groupname;
	} else {
		return $False;
	}

	foreach ($group in $groups)	{
		# Compute groupname hash for caching membership
		$membership_hash = [System.BitConverter]::ToString($_md5.ComputeHash($_utf8.GetBytes($group)));
	
		if ($Userlist) {
			if ((Test-Path variable:script:$membership_hash)) {
				$users = (gv -name $membership_hash).value;
			} else {
				$users = Get-QADGroupMember $group -Indirect -Type user -ShowProgress -ProgressThreshold 0;
				Set-Variable -Name $membership_hash -Value $users -Scope script;
			}
		} else {
			if ((Test-Path variable:script:$membership_hash)) {
				$subgroups = (gv -name $membership_hash).value | ? {$_.Type -eq "group"};
				$users = (gv -name $membership_hash).value | ? {$_.Type -eq "user"};
			} else {
				$subgroups = Get-QADGroupMember $group -Type group -ShowProgress -ProgressThreshold 0;
				$users = Get-QADGroupMember $group -Type user -ShowProgress -ProgressThreshold 0;
				Set-Variable -Name $membership_hash -Value ([array]$users + [array]$subgroups) -Scope script;
			}
		}
		
		if ($UserListTree -and $iteration -ne $null) {
			Set-Variable -Name output -Value ($script:output += "$ident$group") -Scope script;
		}
		
		if ($users) {
			$user_members = @();
			foreach ($user in $users) {
				$user_members += ,$("$ident$identer" + $user.displayName + " ($user)");
			}
			Set-Variable -Name output -Value ($script:output += $($user_members| Sort-Object -Unique -CaseSensitive)) -Scope script;
		}

		if ($subgroups) {
			if ($UserListTree) {
				$iteration++;
			}
			foreach ($subgroup in $subgroups) {
				Get-GroupMembers -groupname $subgroup -iteration $iteration;
			}
		}
	}
}

#############
# LIBRARIES #
#############
# --------- Include stdlib library ---------
. LoadLibrary "stdlib";
trap {stdlib_Notify $_;}
. LoadLibrary "mysql";

##################
# PROGRAM START! #
##################
$startDate = Get-Date;

#check input parameters
if([System.IO.Directory]::Exists($path) -eq $false){
    throw (new-object System.IO.DirectoryNotFoundException("Directory does not exist or is missing!")) ;
}
If($path.EndsWith("\"))
{
    $path = $path.Remove($path.Length-1, 1) ;
}

# Connect to ARS
if ($QADConnection.Type -ne "ARS" -and ($Userlist -or $UserlistTree)) {
	Connect-QADService -Proxy $ARSServer 2>&1 > $Null;
}

#Build information for the header of the output file, if file exist it will be owerwritten! 
$header = $newLine + $("-" * ("Analyzed path: " + $path).Length);
$header += "${newLine}Start: " + $startDate + $newLine;
if ($Csv) {
	$header += "Print results as CSV" + $newLine;
	$csvrow = @{
		Path = "";
		POwner = "";
		PGroup = "";
		Permission = "";
		ApplyTo = "";
		Inheritance = "";
		PType = ""
	};
}
if ($DBName) {
	$header += "Results will be exported to database '$DBName'" + $newLine;
}
$header += "Analyzed path: " + $path + $newLine;
$header += "Parameters:${newline} "
if (!$WithFiles) { $header += "no "; }
$header += "files, ";
if (!$ShowSDDL) { $header += "no "; }
$header += "SDDL, ";
if (!$IncludeInherited) { $header += "no "; }
$header += "inherited${newline} ";
if (!$IncludeOwner) { $header += "no "; }
$header += "owner, ";
if (!$UserlistTree) { $header += "no "; }
$header += "membership tree${newline} ";
if (!$Userlist) { $header += "no "; }
$header += "membership, ";
if (!$IncludeListPermissions) { $header += "no "; }
$header += "list access${newline} ";
if (!$IncludeTechnicalPermissions) { $header += "no "; }
$header += "technical access, ";
if ($Single) { $header += "no "; }
$header += "subfolders${newline}";
if (!$SkipInheritedOnDirectlyAssigned) { $header += " no"; }
$header += " skip inherited with directly assigned${newline}";
if (!$SkipUnusual) { $header += " no"; }
$header += " skip unusual permissions${newline}";
$header += " print ";
if ($GroupnamesOnly) { $header += "groups only"; }
else { $header += "all"; }
if ($Depth) { $header += ", depth is $Depth"; }
$header += $newLine;
$header += $("-" * ("Analyzed path: " + $path).Length);
if ($Csv) {
	write-host $header;
	echo (
		'"Path",' +
		'"Folder Owner",' +
		'"Object",' +
		'"Permission",' +
		'"Apply To",' +
		'"Is Inherited",' +
		'"Access Type"'
	);
} else {
	$header;
}

if ($DBName) {
	# Create tabeles if not exists
	$sql = "CREATE TABLE IF NOT EXISTS ``$db_tbl_paths`` (
		``id`` VARCHAR(40) NOT NULL,
		``path`` TEXT NOT NULL,
		``owner`` VARCHAR(255) NULL DEFAULT NULL,
		``is_inherited`` TINYINT(1) NULL DEFAULT '0',
		``removedfromfs`` TINYINT(1) NULL,
		``lastchecked`` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
		PRIMARY KEY (``id``),
		FULLTEXT INDEX ``path`` (``path``)
	)
	COLLATE='utf8_general_ci'
	ENGINE=InnoDB;
	";
	mysql_execSQL $db_name $sql;
	$sql ="CREATE TABLE IF NOT EXISTS ``$db_tbl_permissions`` (
		``path_id`` VARCHAR(40) NOT NULL,
		``control_type`` VARCHAR(50) NULL DEFAULT NULL,
		``permission_type`` VARCHAR(50) NOT NULL,
		``is_inherited`` TINYINT(1) NULL DEFAULT NULL,
		``object_sid`` VARCHAR(255) NOT NULL,
		``object_name`` VARCHAR(255) NULL DEFAULT NULL,
		``lastchecked`` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
		PRIMARY KEY (``path_id``, ``permission_type``, ``object_sid``)
	)
	COLLATE='utf8_general_ci'
	ENGINE=InnoDB;
	";
	mysql_execSQL $db_name $sql;
}

# Top level
if (!$WithFiles) {
	[System.IO.DirectoryInfo]$rootInfo = New-Object System.IO.DirectoryInfo($path) | ? {$_.Attributes -match 'Directory'};
} else {
	[System.IO.DirectoryInfo]$rootInfo = New-Object System.IO.DirectoryInfo($path);
}
$_folderStack.Push($rootInfo);

$j = 0;
$jj = 1; # Total for progress bar
while ($_folderStack.Count -ne 0) {
    $actualItem = $_folderStack.Pop();
	if ($actualItem.FullName -match 'DfsrPrivate$') {
		continue;
	}
	if ((([regex]::Matches($actualItem.Fullname, '\\')).Count - ([regex]::Matches($Path, '\\')).Count) -gt $Depth) {
		continue;
	}
	$j++;
	Write-Progress -Id 1 -Activity "Reading filesystem information" -Status "$j/$jj" -CurrentOperation ("Processing " + $actualItem.Fullname) -PercentComplete ($j / $jj * 100);

    #add children to stack
    if ($actualItem -is [System.IO.DirectoryInfo]) {

		Try {
			$isDenied = $False;
			if ($WithFiles) {
				[System.IO.FileSystemInfo[]]$dirs = $actualItem.GetFileSystemInfos() | Sort-Object Name -Descending;
			} else {
				[System.IO.DirectoryInfo[]]$dirs = $actualItem.GetDirectories() | Sort-Object Name -Descending;
			}
		}
		Catch {
			if ($_.Exception.InnerException -match "Access to the path .* is denied." -or $_.Exception.InnerException -match "The parameter is incorrect") {
				rv dirs -ErrorAction SilentlyContinue;
				$isDenied = $($newLine + $actualItem.FullName + "${newLine}${identer}Cannot read ACL, do not have enough permissions");
			} elseif ($_.Exception.InnerException -match "The specified path, file name, or both are too long") {
				rv dirs -ErrorAction SilentlyContinue;
				$isDenied = $($newLine + "\\...\" + $actualItem.Name + "${newLine}${identer}Cannot read subfolder, the fully qualified name is too long");
			} else {
				throw $_;
			}
		}
		if ($dirs -and !$Single) {
            foreach ($dir in $dirs) {
                $_folderStack.Push($dir);
				$jj++;
            }
        }
    }
    
	if ($isDenied) {
		if ($Csv) {
			$csvrow = @{
				Path = $actualItem.FullName;
				POwner = $isDenied -replace "$identer" -replace ".*$newLine";
			};
			echo (
				'"' + $csvrow['Path'] + '",' +
				'"' + $csvrow['POwner'] + '"'
			);
		} elseif ($DBName -and $actualItem.FullName) {
			$id = Get-Hash($actualItem.FullName);
			$path = mysql_Escape($actualItem.FullName);
			$sql = "INSERT INTO $db_tbl_paths (``id``,``path``,``lastchecked``) VALUES ('$id','$path',now()) ON DUPLICATE KEY UPDATE ``path``='$path',``lastchecked``=now();";
			mysql_execSQL $db_name $sql;
		} else {
			$isDenied;
		}				
		continue;
	}

	if (!$actualItem.FullName) {
		$noFullName = "Cannot determine fullname for '" + $actualItem.Name + "'. Skipped!";
		if ($Csv) {
			$csvrow = @{
				Path = $actualItem.FullName;
				POwner = "Cannot determine fullname, skipped";
			};
			echo (
				'"' + $csvrow['Path'] + '",' +
				'"' + $csvrow['POwner'] + '"'
			);
		} else {
			$noFullName;
		}
		continue;
	}
    
	try {
		$aclActFile = @();
		$aclActFile = (Get-Item -Force -LiteralPath $actualItem.FullName).GetAccessControl();
	} catch {
		if ($_.Exception -match 'unauthorized') {
			$isDenied = $($newLine + $actualItem.FullName + "${newLine}${identer}Cannot read ACL, do not have enough permissions");
			if ($Csv) {
				$csvrow = @{
					Path = $actualItem.FullName;
					POwner = $isDenied -replace "$identer" -replace ".*$newLine";
				};
				echo (
					'"' + $csvrow['Path'] + '",' +
					'"' + $csvrow['POwner'] + '"'
				);
			} else {
				$isDenied;
			}
		}
	}
	
	if (!$GroupnamesOnly -and !$Csv) {
		$WriteFileHeader = $true;
	}

	$output = @();
	$hasInherited = $False;
	$hasUnusual = $False;
	
	$Accesses = $aclActFile.Access | Sort-Object -Property IsInherited,FileSystemRights,IdentityReference;
	
	if ($Accesses | ? {$_.IsInherited -eq $False}) {
		$hasInherited = $True;
	}
	If (!$SkipUnusual -and ($Accesses | ? {($_.InheritanceFlags -eq "None" -and $_.IdentityReference -notmatch '\. L$') -or $_.IdentityReference -match "^S-"})) {
		$hasUnusual = $True;
	}
	
	for ($i = 0; $i -lt $Accesses.Count; $i++) {
		$Access = $Accesses[$i];
		$Inherited = [string]$Access.IsInherited;
        if (($hasInherited -and !$SkipInheritedOnDirectlyAssigned) -or $hasUnusual -or $Inherited -eq "False" -or $IncludeInherited -or $actualItem -eq $rootInfo) {
			if (!$IncludeTechnicalPermissions -and $WellKnownIdentityReferences -contains $Access.IdentityReference) {
				continue;
			}
		
            #write File Header
            if ($WriteFileHeader) {
				if ($ShowSDDL) {
					$fileHeader = $newLine + $actualItem.FullName + " [" + $aclActFile.Sddl + "]";
				} else {
					$fileHeader = $newLine + $actualItem.FullName;
				}
				if ($IncludeOwner -and ($WellKnownIdentityReferences -notcontains $aclActFile.Owner -or $IncludeTechnicalPermissions)) {
					$fileHeader += "${newLine}${identer}OWNER:" + $aclActFile.Owner;
				}
				if (!$Csv) {
					$fileHeader;
				}
                $WriteFileHeader = $false;
            }

			# Get access type
			if ($Access.FileSystemRights -match '^ReadAndExecute' -and $Access.InheritanceFlags -notmatch "ObjectInherit") {
				$accessType = "LIST";
			} elseif ($Access.InheritanceFlags -notmatch "ObjectInherit" -and -not $IncludeListPermissions) {
				#continue;
				$accessType = ($Access.FileSystemRights -split(','))[0].ToUpper();
			} else {
				switch (($Access.FileSystemRights -split(','))[0].ToUpper()) {
					MODIFY {$accessType = "WRITE";}
					READANDEXECUTE {$accessType = "READ";}
					FULLCONTROL {$accessType = "FULL";}
					default {$accessType = ($Access.FileSystemRights -split(','))[0].ToUpper();}
				}
			}
			if ($Inherited -eq "True") {
				$accessType += "(inherited)";
			}
			
			# Skip list permission
			if ($accessType -match "^LIST" -and !$IncludeListPermissions) {continue;}
			
			if (!$GroupnamesOnly) {
				$output += ,$("$identer" + $accessType + ":" + $Access.IdentityReference);
			} else {
				$output += ,$($Access.IdentityReference);
			}

			if ($Access.InheritanceFlags -eq "None" -and !$GroupnamesOnly) {
				$output[-1] += " (apply to this folder only, not inherited by children)";
			}

			if ($Userlist -or $UserListTree) {
				try {
					if ($Access.IdentityReference.Value -match '^[A-z]*\\') {
						$grouplist = [array](Get-QADGroup -SizeLimit 0 -Identity $Access.IdentityReference.Value);
					} else {
						throw "Wrong domain!";
					}
				} catch {
					$grouplist = $Null;
				}
				if ($grouplist.count) {
					$ii = 0;
					foreach ($groupname in $grouplist) {
						$ii++;
						Write-Progress -Id 2 -Activity "Extracting membership information from Active Directory" -Status ("$ii/" + $grouplist.count) -CurrentOperation "Processing $groupname" -PercentComplete ($ii/$grouplist.count * 100);
						get-groupmembers -groupname $groupname;
					}
				} else {
					$output[-1] += ," (Cannot get membership, not a group?)";
				}
			}
			
			if ($Csv) {
				$csvrow = @{
					Path = $actualItem.FullName;
					POwner = $aclActFile.Owner;
					PGroup = $Access.IdentityReference;
					Permission = $accessType;
					ApplyTo = $Access.InheritanceFlags;
					Inheritance = $Inherited;
					PType = $Access.AccessControlType;
				};
				switch ($Access.InheritanceFlags) {
					'None' {$csvrow['ApplyTo'] = "This folder only";}
					'ObjectInherit' {$csvrow['ApplyTo'] = "This folder and files";}
					'ContainerInherit' {$csvrow['ApplyTo'] = "This folder and subfolders";}
					'ContainerInherit, ObjectInherit' {$csvrow['ApplyTo'] = "This folder, subfolders and files";}
					default {$csvrow['ApplyTo'] = "Unknown";}
				}
				echo (
					'"' + $csvrow['Path'] + '",' +
					'"' + $csvrow['POwner'] + '",' +
					'"' + $csvrow['PGroup'] + '",' +
					'"' + $csvrow['Permission'] + '",' +
					'"' + $csvrow['ApplyTo'] + '",' +
					'"' + $csvrow['Inheritance'] + '",' +
					'"' + $csvrow['PType'] + '"'
				);
			}
			
			if ($DBName) {
				if ($id -ne (Get-Hash($actualItem.FullName))) {
					$id = Get-Hash($actualItem.FullName);
					$path = mysql_Escape($actualItem.FullName);
					$owner = mysql_Escape($aclActFile.Owner);
					[int]$is_inherited = $hasInherited;
					$sql = "INSERT INTO $db_tbl_paths (``id``,``path``,``owner``,``is_inherited``,``removedfromfs``,``lastchecked``) VALUES ('$id','$path','$owner','$is_inherited',0,now()) ON DUPLICATE KEY UPDATE ``path``='$path',``owner``='$owner',``is_inherited``='$is_inherited',``removedfromfs``=0,``lastchecked``=now();";
					mysql_execSQL $db_name $sql;
				}
				$control_type = mysql_Escape($access.AccessControlType);
				$permission_type = mysql_Escape($accessType);
				if ($Inherited -eq "True") {
					$is_inherited = 1;
				} else {
					$is_inherited = 0;
				}
				$object_sid = mysql_Escape($access.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value);
				$object_name = mysql_Escape($access.IdentityReference.Value);
				$sql = "INSERT INTO $db_tbl_permissions (``path_id``,``control_type``,``permission_type``,``is_inherited``,``object_sid``,``object_name``,``lastchecked``) VALUES ('$id','$control_type','$permission_type','$is_inherited','$object_sid','$object_name',now()) ON DUPLICATE KEY UPDATE ``control_type``='$control_type',``permission_type``='$permission_type',``is_inherited``='$is_inherited',``object_sid``='$object_sid',``object_name``='$object_name',``lastchecked``=now();";
				mysql_execSQL $db_name $sql;
			}
        }
    }
	if (!$Csv -and !$DBName) {
		$output;
	}
}
if (!$accessType) {
	$output = "${newline}No objects corresponding this parameters...";
	if ($Csv) {
		write-host $output;
	} else {
		$output;
	}
}

#Footer
$endDate = Get-Date;
$elapsedTime = $endDate - $startDate;
$footer = "" + $newLine + $("-" * ("Analyzed path: " + $path).Length) + "${newLine}Run completed at: " + $endDate + $newLine + "Elapsed Time: " + $elapsedTime + $newLine + $("-" * ("Analyzed path: " + $path).Length);
if ($Csv) {
	write-host $footer;
} else {
	$footer;
}
