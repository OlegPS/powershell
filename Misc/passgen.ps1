# Generate passwords

param ($Length)

if ($Length -lt 3 -or $Length -gt 100) { $Length = 8; }

$Caps = [char[]] "ABCDEFGHIJKLMNOPQRSTUVWXYZ" * 3;
$Lows = [char[]] "abcdefghjkmnopqrstuvwxyz" * 3;
$Nums = [char[]] "0123456789" * 5;
$Syms = [char[]] "!@#$%()&[]{}/\<>" * 3;

while ($CapsPreCount -le 1) {
	$CapsPreCount = $Length%$(Get-Random -Minimum 1 -Maximum ($Length - 3));
}
$CapsCount = Get-Random -Minimum 1 -Maximum $CapsPreCount;
$LowsCount = Get-Random -Minimum 1 -Maximum ($Length - $CapsCount - 2);
$NumsCount = Get-Random -Minimum 1 -Maximum ($Length - $CapsCount - $LowsCount - 1);
$SymsCount = $Length - $CapsCount - $LowsCount - $NumsCount;
$Passwd = [string](@($Caps | Get-Random -Count $CapsCount) + @($Lows | Get-Random -Count $LowsCount) + @($Nums | Get-Random -Count $NumsCount) + @($Syms | Get-Random -Count $SymsCount) | Get-Random -Count $Length) ;

return $($Passwd.Replace(' ',''));