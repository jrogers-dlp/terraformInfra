# Specify the provider and access details
provider "aws" {
  region = "us-west-2"
}
/*
# Default security group to access the instances via WinRM over HTTP and HTTPS
resource "aws_security_group" "default" {
  name        = "terraform_example"
  description = "Used in the terraform"

  # WinRM access from anywhere
  ingress {
    from_port   = 5985
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Lookup the correct AMI based on the region specified
data "aws_ami" "amazon_windows_2012R2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2012-R2_RTM-English-64Bit-Base-*"]
  }
}
*/
variable "db_password"{
  type = string
}
variable "octo_master_key"{
  type = string
}
variable "octo_password"{
  type = string
}
variable "user_password"{
  type = string
}
data "aws_db_instance" "octo_db" {
  db_instance_identifier = "octopusdeploy"
}
locals {
  db_endpoint = data.aws_db_instance.octo_db.address
  db_name = "OctopusDeploy-OctopusServer"
  db_admin = "admin"
  db_password = var.db_password
  db_master_key = var.octo_master_key
  octo_admin = "j.rogers"
  octo_password = var.octo_password
  octo_email = "j.rogers@wearedoubleline.com"
  octo_instance_name = "OctopusServer"
  octo_server_name = "OctopusDeploy"
  octo_license = base64encode(file("./OctopusLic.txt"))
}


resource "aws_instance" "octo" {
  instance_type = "t3.medium"
  ami           = "ami-0afb7a78e89642197"
  # ami           = "${data.aws_ami.amazon_windows_2012R2.image_id}"

  key_name = "jrogers-kp"
  get_password_data = true
  vpc_security_group_ids = ["sg-0e47e07daae5a3c59"]
  associate_public_ip_address = true
  #Start-BitsTransfer -Source https://download.octopusdeploy.com/octopus/Octopus.2020.4.6-x64.msi -Destination C:\temp\Octopus.msi
  user_data = <<EOF
<powershell>
  net user 'j.rogers' ${var.user_password} /add /y
  net localgroup administrators j.rogers /add
  function Get-FileFromURL {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [System.Uri]$URL,
        [Parameter(Mandatory, Position = 1)]
        [string]$Filename
    )

    process {
        try {
            $request = [System.Net.HttpWebRequest]::Create($URL)
            $request.set_Timeout(5000) # 5 second timeout
            $response = $request.GetResponse()
            $total_bytes = $response.ContentLength
            $response_stream = $response.GetResponseStream()

            try {
                $buffer = New-Object -TypeName byte[] -ArgumentList 256KB
                $target_stream = [System.IO.File]::Create($Filename)

                $timer = New-Object -TypeName timers.timer
                $timer.Interval = 1000 # Update progress every second
                #$timer_event = Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action {
                #    $Global:update_progress = $true
                #}
                $timer.Start()

                do {
                    $count = $response_stream.Read($buffer, 0, $buffer.length)
                    $target_stream.Write($buffer, 0, $count)
                    $downloaded_bytes = $downloaded_bytes + $count

                    if ($Global:update_progress) {
                        $percent = $downloaded_bytes / $total_bytes
                        $status = @{
                            completed  = "{0,6:p2} Completed" -f $percent
                            downloaded = "{0:n0} MB of {1:n0} MB" -f ($downloaded_bytes / 1MB), ($total_bytes / 1MB)
                            speed      = "{0,7:n0} KB/s" -f (($downloaded_bytes - $prev_downloaded_bytes) / 1KB)
                            eta        = "eta {0:hh\:mm\:ss}" -f (New-TimeSpan -Seconds (($total_bytes - $downloaded_bytes) / ($downloaded_bytes - $prev_downloaded_bytes)))
                        }
                        $progress_args = @{
                            Activity        = "Downloading $URL"
                            Status          = "$($status.completed) ($($status.downloaded)) $($status.speed) $($status.eta)"
                            PercentComplete = $percent * 100
                        }
                        Write-Progress @progress_args

                        $prev_downloaded_bytes = $downloaded_bytes
                        $Global:update_progress = $false
                    }
                } while ($count -gt 0)
            }
            finally {
                if ($timer) { $timer.Stop() }
                #if ($timer_event) { Unregister-Event -SubscriptionId $timer_event.Id }
                if ($target_stream) { $target_stream.Dispose() }
                # If file exists and $count is not zero or $null, than script was interrupted by user
                if ((Test-Path $Filename) -and $count) { Remove-Item -Path $Filename }
            }
        }
        finally {
            if ($response) { $response.Dispose() }
            if ($response_stream) { $response_stream.Dispose() }
        }
    }
  }
  if($env:ComputerName -notlike "*Octo*"){
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
    
    mkdir C:\temp
    Get-FileFromURL https://download.octopusdeploy.com/octopus/Octopus.2020.4.6-x64.msi C:\temp\Octopus.msi
    Rename-Computer -NewName ${local.octo_server_name} -Restart
  }
  if(!(Test-Path "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe")){
    msiexec /i C:\temp\Octopus.msi /quiet RUNMANAGERONEXIT=no
    Start-Sleep -s 30
    Restart-Computer -force
  }else {
    $error.clear()
    Get-Service "OctopusDeploy"
    if($error) {
      & "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe" create-instance --instance ${local.octo_instance_name} --config "C:\Octopus\OctopusServer.config" --serverNodeName ${local.octo_server_name}
      & "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe" database --instance ${local.octo_instance_name} --connectionString "Data Source=${local.db_endpoint};Initial Catalog=${local.db_name};Integrated Security=False;User ID=${local.db_admin};Password=${local.db_password}" --masterKey ${local.db_master_key}
      & "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe" configure --instance ${local.octo_instance_name} --webForceSSL "False" --webListenPrefixes "http://localhost:80/" --commsListenPort "10943" --usernamePasswordIsEnabled "True" --activeDirectoryIsEnabled "False"
      & "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe" service --instance ${local.octo_instance_name} --stop
      & "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe" admin --instance ${local.octo_instance_name} --username ${local.octo_admin} --email ${local.octo_email} --password ${local.octo_password}
      & "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe" license --instance ${local.octo_instance_name} --licenseBase64 ${local.octo_license}
      & "C:\Program Files\Octopus Deploy\Octopus\Octopus.Server.exe" service --instance ${local.octo_instance_name} --install --reconfigure --start
      
    }else { Write-Host "Octopus is already installed"}
  }
</powershell>
<persist>true</persist>
EOF
}

output "public_ip" {
  value = aws_instance.octo.public_ip
}

