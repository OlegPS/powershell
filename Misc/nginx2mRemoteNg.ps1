# Fill mRemoteNg connections tab from nginx upstream config

$mRemoteNgConfigFilePath = "C:\Users\oleg.selin\bin\mRemoteNG\confCons.xml";
$defaultRdpUsername = "oleg.selin";
#$defaultRdpDomain = "";
#$defaultSshUsername = "oleg.selin";
#$defaultRdpPassword = read-host "Please type in default password for RDP connections";
#$defaultSshPassword = read-host "Please type in default password for SSH connections";
$nginxIp = "127.0.0.1";
$nginxUser = "oleg.selin";
$nginxPassword = read-host "Please type in password for $nginxUser@$nginxIp";
$nginxUpstreamFilePath = "/etc/nginx/upstreams.conf";

$confCons = [xml](gc $mRemoteNgConfigFilePath);
$confNginx = plink -pw $nginxPassword  $nginxUser@$nginxIp cat $nginxUpstreamFilePath;
$confConsNew = @();
$addedContainers = @();
$addedRemotes = @{};
foreach ($line in $confNginx) {
	if ($line -match '^(\s*|\s*#.*)$') {
		continue;
	}
	if ($container -and $line -match '}') {
		if ($addedContainers -contains $container) {
			$confConsNew += ,"`t</Node>";
		}
		rv -ea 0 container, confConsContainer,confConsNode,ip,name,username,password,panel;
	}
	if ($container -and $line.trim() -match 'server\s+') {
		$ip = $line.trim() -replace '^server\s+(((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)):([0-9]+)(;|\s+).*$', '$1';
		if ($addedRemotes.Keys -contains $ip) {
			continue;
		}
		if ($addedContainers -notcontains $container) {
			$confConsNew += ,"`t<Node Name='$container' Type='Container' Expanded='False' Descr='GeneratedAutomatically' Icon='mRemoteNG' Panel='Главная' Username='' Domain='' Password='' Hostname='' Protocol='RDP' PuttySession='Default Settings' Port='3389' ConnectToConsole='False' UseCredSsp='True' RenderingEngine='IE' ICAEncryptionStrength='EncrBasic' RDPAuthenticationLevel='NoAuth' LoadBalanceInfo='' Colors='Colors16Bit' Resolution='FitToWindow' AutomaticResize='True' DisplayWallpaper='False' DisplayThemes='False' EnableFontSmoothing='False' EnableDesktopComposition='False' CacheBitmaps='True' RedirectDiskDrives='False' RedirectPorts='False' RedirectPrinters='False' RedirectSmartCards='False' RedirectSound='DoNotPlay' RedirectKeys='False' Connected='False' PreExtApp='' PostExtApp='' MacAddress='' UserField='' ExtApp='' VNCCompression='CompNone' VNCEncoding='EncHextile' VNCAuthMode='AuthVNC' VNCProxyType='ProxyNone' VNCProxyIP='' VNCProxyPort='0' VNCProxyUsername='' VNCProxyPassword='' VNCColors='ColNormal' VNCSmartSizeMode='SmartSAspect' VNCViewOnly='False' RDGatewayUsageMethod='Never' RDGatewayHostname='' RDGatewayUseConnectionCredentials='Yes' RDGatewayUsername='' RDGatewayPassword='' RDGatewayDomain='' InheritCacheBitmaps='False' InheritColors='False' InheritDescription='False' InheritDisplayThemes='False' InheritDisplayWallpaper='False' InheritEnableFontSmoothing='False' InheritEnableDesktopComposition='False' InheritDomain='False' InheritIcon='False' InheritPanel='False' InheritPassword='False' InheritPort='False' InheritProtocol='False' InheritPuttySession='False' InheritRedirectDiskDrives='False' InheritRedirectKeys='False' InheritRedirectPorts='False' InheritRedirectPrinters='False' InheritRedirectSmartCards='False' InheritRedirectSound='False' InheritResolution='False' InheritAutomaticResize='False' InheritUseConsoleSession='False' InheritUseCredSsp='False' InheritRenderingEngine='False' InheritUsername='False' InheritICAEncryptionStrength='False' InheritRDPAuthenticationLevel='False' InheritLoadBalanceInfo='False' InheritPreExtApp='False' InheritPostExtApp='False' InheritMacAddress='False' InheritUserField='False' InheritExtApp='False' InheritVNCCompression='False' InheritVNCEncoding='False' InheritVNCAuthMode='False' InheritVNCProxyType='False' InheritVNCProxyIP='False' InheritVNCProxyPort='False' InheritVNCProxyUsername='False' InheritVNCProxyPassword='False' InheritVNCColors='False' InheritVNCSmartSizeMode='False' InheritVNCViewOnly='False' InheritRDGatewayUsageMethod='False' InheritRDGatewayHostname='False' InheritRDGatewayUseConnectionCredentials='False' InheritRDGatewayUsername='False' InheritRDGatewayPassword='False' InheritRDGatewayDomain='False'>";
			"[$container]";
			$addedContainers += ,$container;
			$confCons.connections.SelectNodes("Node[@Name='$container' and @Type='Container' and @Descr='GeneratedAutomatically']") | % {
				$_.ParentNode.RemoveChild($_) | Out-Null;
			}
		}
		$addedRemotes.Add($ip, $Null);
		$name = $ip -replace '^.*\.([0-9]+)$', '$1';
		$panel = $ip -replace '[0-9]+$';
		if (!$addedRemotes[$ip] -and (ping -n 1 -w 1 -4 $ip | select-string 'TTL=63')) {
			$addedRemotes[$ip] = "SSH2";
			if (!$password) {
				$password = $defaultSshPassword;
			}
			if (!$username) {
				$username = $defaultSshUsername;
			}
		} else {
			$addedRemotes[$ip] = "RDP";
			if (!$password) {
				$password = $defaultRdpPassword;
			}
			if (!$username) {
				$username = $defaultRdpUsername;
			}
		}
		if (!$domain) {
			$domain = $defaultRdpDomain;
		}
		$protocol = $addedRemotes[$ip];
		$confConsNew += ,"`t`t<Node Name='$name' Type='Connection' Descr='$ip' Icon='mRemoteNG' Panel='$panel' Username='$username' Domain='$domain' Password='$password' Hostname='$ip' Protocol='$protocol' PuttySession='Default Settings' Port='3389' ConnectToConsole='False' UseCredSsp='True' RenderingEngine='IE' ICAEncryptionStrength='EncrBasic' RDPAuthenticationLevel='NoAuth' LoadBalanceInfo='' Colors='Colors16Bit' Resolution='FitToWindow' AutomaticResize='True' DisplayWallpaper='False' DisplayThemes='False' EnableFontSmoothing='False' EnableDesktopComposition='False' CacheBitmaps='True' RedirectDiskDrives='False' RedirectPorts='False' RedirectPrinters='False' RedirectSmartCards='False' RedirectSound='DoNotPlay' RedirectKeys='False' Connected='False' PreExtApp='' PostExtApp='' MacAddress='' UserField='' ExtApp='' VNCCompression='CompNone' VNCEncoding='EncHextile' VNCAuthMode='AuthVNC' VNCProxyType='ProxyNone' VNCProxyIP='' VNCProxyPort='0' VNCProxyUsername='' VNCProxyPassword='' VNCColors='ColNormal' VNCSmartSizeMode='SmartSAspect' VNCViewOnly='False' RDGatewayUsageMethod='Never' RDGatewayHostname='' RDGatewayUseConnectionCredentials='Yes' RDGatewayUsername='' RDGatewayPassword='' RDGatewayDomain='' InheritCacheBitmaps='False' InheritColors='False' InheritDescription='False' InheritDisplayThemes='False' InheritDisplayWallpaper='False' InheritEnableFontSmoothing='False' InheritEnableDesktopComposition='False' InheritDomain='False' InheritIcon='False' InheritPanel='False' InheritPassword='False' InheritPort='False' InheritProtocol='False' InheritPuttySession='False' InheritRedirectDiskDrives='False' InheritRedirectKeys='False' InheritRedirectPorts='False' InheritRedirectPrinters='False' InheritRedirectSmartCards='False' InheritRedirectSound='False' InheritResolution='False' InheritAutomaticResize='False' InheritUseConsoleSession='False' InheritUseCredSsp='False' InheritRenderingEngine='False' InheritUsername='False' InheritICAEncryptionStrength='False' InheritRDPAuthenticationLevel='False' InheritLoadBalanceInfo='False' InheritPreExtApp='False' InheritPostExtApp='False' InheritMacAddress='False' InheritUserField='False' InheritExtApp='False' InheritVNCCompression='False' InheritVNCEncoding='False' InheritVNCAuthMode='False' InheritVNCProxyType='False' InheritVNCProxyIP='False' InheritVNCProxyPort='False' InheritVNCProxyUsername='False' InheritVNCProxyPassword='False' InheritVNCColors='False' InheritVNCSmartSizeMode='False' InheritVNCViewOnly='False' InheritRDGatewayUsageMethod='False' InheritRDGatewayHostname='False' InheritRDGatewayUseConnectionCredentials='False' InheritRDGatewayUsername='False' InheritRDGatewayPassword='False' InheritRDGatewayDomain='False' />";
		"`t$ip";
	}
	if ($line.trim() -match '^upstream\s+') {
		$container = $line.trim() -replace '^upstream\s+([A-z0-9_]+).*$', '$1';
		if ($confConsContainer = $confCons.Connections.Node | ? {$_.Name -eq "$container" -and $_.Type -eq "Container"}) {
			$confConsNode = $confConsContainer.Node | select -f 1;
		}
		if (!$password) {
			$password = $confConsNode.password;
		}
		if (!$username) {
			$username = $confConsNode.username;
		}
		if (!$domain) {
			$domain = $confConsNode.domain;
		}
	}
}
if ($confConsNew) {
	#$confCons.connections.SelectNodes("Node[@Descr='GeneratedAutomatically']") | % {
	#	$_.ParentNode.RemoveChild($_) | Out-Null;
	#}
	([xml]("<connections>" + [string]$confConsNew + "</connections>")).SelectNodes("//connections/Node") | % {
		$newNode = $confCons.ImportNode($_, $true);
		$confCons.connections.AppendChild($newNode) | Out-Null;
	}
	cp $mRemoteNgConfigFilePath ($mRemoteNgConfigFilePath + "." + ((get-date -uformat %s) -replace ',.*$') + ".bak")
	if (!$?) {
		throw $error[0];
	}	
	$confCons.Save($mRemoteNgConfigFilePath);
	"Done! please reload mRemoteNG connections file!";
}