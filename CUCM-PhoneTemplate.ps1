######################################
#  Dickering with CUCM REST APIs v1  #
#  Dickering done by Ed Medeiros     #
#                                    #
#   I am not a programmamer....      #
######################################


# This is messy as hell but i am not a programmammer so just took a lot of dickering with postman / PS to work.
# Need ALL line fields filled out and will not work with EM profiles.
# 
# WHAT THIS DONE DOES:
# Asks for 4 pieces of info:  Main device MAC, additonal description info, extension, and user ID
# Pulls LDAP info from ccm end user page and populates caller ID on all associated lines for the extension you input.
# Creates CSF device
# Makes all device end-user / owner ID associations.
# 

#Who needs a CA?   Not this guy.
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@

[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy 

#############################
### BEGIN BELOW THIS PART ###
#############################

### ME YAMMERING (README) SECTION.   PUT IN BLOCKS SO I CAN MINIMIZE IT.  NO ONE WANTS TO HEAR ME YAMMERING. ###
<#{
### This pulls info from end user page such as first name, lastname, etc and populates the caller ID fields, 
### device / owner associations / Creates CSF /  yaddda yadda.  Ultimately (again), I would like to
### put this on intranet site so security users can update phones themselves and not bother us.
### Voicemail creation does not work.   Can delete though if no dependencies.
### P.S.  Only I would be dumb enough to write a script to automate 50% of my workload...
### End of yammering.
}#>



### Folks will need the "Standard AXL Access" (or something like that) role assigned in CUCM for this to work.
$creds = Get-Credential

Write-Host 
@"
##############################################

Welcome to the Call Mangler Update Application

##############################################


"@

$MAC = Read-Host @"
Enter the MAC address of the primary phone the user will use.
This can be found on the back of the phone on a sticker with a string of digits labeled 'MAC'.
Valid Characters are 0-9 and A-F
"@
$phone = "SEP"+$MAC
$description = Read-Host "Enter any other description info you would like to add to the user's primary phone, such as room number.  This can be left blank."
$extension = Read-Host "Enter the extension you wish to update"
$userID = Read-Host "enter the alias of the user you wish to update"
$jabber = "CSF"+$userID


# SOAP Headers Yonder:
$headers = @{
    'SOAPAction' = 'CUCM:DBver=11.5';
    'Authorization' = 'Basic #####';  #####USE POSTMAN TO GET HASH VALUE OF PASSWORD OR NO TRABAJO.  REPLACE THE POUND TOWN IN AUTH HEADER WITH HASH.
    'Content-Type' = 'text/xml;charset=UTF-8';}

# Hashtable for XML namespaces over yonder:
$namespace = @{
soapenv = "http://schemas.xmlsoap.org/soap/envelope/";
ns = "http://www.cisco.com/AXL/API/11.5";}


##### 'Get' APIs Yonder:
$phoneRequest= @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/11.5">
    <soapenv:Header/>
    <soapenv:Body>
        <ns:getPhone>
            <name>$phone</name>
        </ns:getPhone>
    </soapenv:Body>
</soapenv:Envelope>
"@

$lineRequest=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/11.5">
    <soapenv:Header/>
    <soapenv:Body>
        <ns:getLine>
            <pattern>$extension</pattern>
            <routePartitionName>PT_JOCO_INTERNAL</routePartitionName>
        </ns:getLine>
    </soapenv:Body>
</soapenv:Envelope>
"@

$userRequest=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/11.5">
    <soapenv:Header/>
    <soapenv:Body>
        <ns:getUser>
            <userid>$userID</userid>
        </ns:getUser>
    </soapenv:Body>
</soapenv:Envelope>
"@
#####

### THIS SECTION OVER YONDER STORES RETURN VALUE OF API FROM CALL MANGLER IN PS VARIABLE ###  
[xml]$API_RequestLine = Invoke-RestMethod -Method Post -Uri "https://#.#.#.#:8443/axl/" -Headers $headers -Body $lineRequest -Credential $creds
[xml]$API_RequestPhone = Invoke-RestMethod -Method Post -Uri "https://#.#.#.#:8443/axl/" -Headers $headers -Body $phoneRequest -Credential $creds
[xml]$API_RequestUser = Invoke-RestMethod -Method Post -Uri "https://#.#.#.#:8443/axl/" -Headers $headers -Body $userRequest -Credential $creds

##### TO DO:  Add something here in case AXL role not assigned to user.  This is where they will get 401 error if they dont have AXL privs...  ###

# Putting various XPATH queries to use with *Select-Xml* yonder:
$XPATH_LineAssociatedDevices = "/soapenv:Envelope/soapenv:Body/ns:getLineResponse/return/line/associatedDevices/device"
$XPATH_LineDescription = "/soapenv:Envelope/soapenv:Body/ns:getLineResponse/return/line/description"
$XPATH_LineAlertingName = "/soapenv:Envelope/soapenv:Body/ns:getLineResponse/return/line/alertingName"
$XPATH_LineAsciiAlertingName = "/soapenv:Envelope/soapenv:Body/ns:getLineResponse/return/line/asciiAlertingName"
$XPATH_PhoneDescription = "/soapenv:Envelope/soapenv:Body/ns:getPhoneResponse/return/phone/description"
$XPATH_UserAssociatedDevices = "/soapenv:Envelope/soapenv:Body/ns:getUserResponse/return/user/associatedDevices"
$XPATH_UserDisplayName = "/soapenv:Envelope/soapenv:Body/ns:getUserResponse/return/user/displayName"
$XPATH_UserFirstName = "/soapenv:Envelope/soapenv:Body/ns:getUserResponse/return/user/firstName"
$XPATH_UserLastName = "/soapenv:Envelope/soapenv:Body/ns:getUserResponse/return/user/lastName"
$XPATH_LineConfig = "/soapenv:Envelope/soapenv:Body/ns:getPhoneResponse/return/phone/lines"


### Grab First and last name for use in caller ID / Label / etc. 
$firstName = Select-Xml -Xml $API_RequestUser -XPath $XPATH_UserFirstName -Namespace $namespace | foreach {$_.Node.InnerXml}
$lastName = Select-Xml -Xml $API_RequestUser -XPath $XPATH_UserLastName -Namespace $namespace | foreach {$_.Node.InnerXml}
$lastInitial = $lastname.Substring(0,1)
$callerID = "$lastName, $firstName"
$associatedDevicesUpload = Select-Xml -Xml $API_RequestLine -XPath $XPATH_LineAssociatedDevices -Namespace $namespace | foreach {"<device>"+$_.Node.InnerXml+"</device>"} 
$associatedDevicesPurdy = Select-Xml -Xml $API_RequestLine -XPath $XPATH_LineAssociatedDevices -Namespace $namespace | foreach {$_.Node.InnerXml+"`n"} 
$fullDescription = "$callerID"+"  $description"

##### Simple 'Update' APIs Yonder:
##### More complicated updates are below.

# update phone description also updates owner 
$updatePhoneDescription= @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/11.5">
    <soapenv:Header/>
    <soapenv:Body>
        <ns:updatePhone>
            <name>$phone</name>
            <description>$fullDescription</description>
            <ownerUserName>$userID</ownerUserName>
        </ns:updatePhone>
    </soapenv:Body>
</soapenv:Envelope>
"@

$updateLine=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/11.5">
    <soapenv:Header/>
    <soapenv:Body>
        <ns:updateLine>
            <pattern>$extension</pattern>
            <description>$callerID</description>
            <routePartitionName>PT_JOCO_INTERNAL</routePartitionName>
            <alertingName>$callerID</alertingName>
            <asciiAlertingName>$callerID</asciiAlertingName>
            <voiceMailProfileName>Default</voiceMailProfileName>
        </ns:updateLine>
    </soapenv:Body>
</soapenv:Envelope>
"@

$updateUser=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/11.5">
    <soapenv:Header/>
    <soapenv:Body>
        <ns:updateUser>
            <userid>$userID</userid>
            <homeCluster>true</homeCluster>
            <imAndPresenceEnable>true</imAndPresenceEnable>
            <calendarPresence>true</calendarPresence>
            <serviceProfile>#####</serviceProfile>
               <primaryExtension>
                  <pattern>$extension</pattern>
                  <routePartitionName>#####</routePartitionName>
               </primaryExtension>
        </ns:updateUser>
    </soapenv:Body>
</soapenv:Envelope>
"@



#####  Add CSF Device Yonder.  
# check if extension starts with  5, 6 ,or 7 and set e164 mask accordingly
# This will only be used to apply *New* CSF e164 mask since it ---===*SHOULD*===--- already be there in devices already applied. 
$beginsWith = $extension.Substring(0,1)
switch($beginsWith){
    5{$e164Mask = "#####"}
    6{$e164Mask = "#####"}
    7{$e164Mask = "#####"}
    default{}
}

$addCSF = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/11.5">
   <soapenv:Header/>
   <soapenv:Body>
      <ns:addPhone>
            <phone>
               <name>$jabber</name>
               <description>$callerID - Jabber Device</description>
               <product>Cisco Unified Client Services Framework</product>
               <model>Cisco Unified Client Services Framework</model>
               <class>Phone</class>
               <protocol>SIP</protocol>
               <protocolSide>User</protocolSide>
               <devicePoolName>#####</devicePoolName>
               <securityProfileName>Cisco Unified Client Services Framework - Standard SIP Non-Secure Profile</securityProfileName>
               <sipProfileName>Standard SIP Profile</sipProfileName>
               <callingSearchSpaceName>#####</callingSearchSpaceName>
               <ownerUserName>$userID</ownerUserName>
               <lines>
                  <line>
                     <index>1</index>
                     <label>$firstName $lastInitial.  $extension</label>
                     <display>$callerID</display>
                     <displayAscii>$callerID</displayAscii>
                     <description>$callerID JABBER DEVICE</description>
                     <e164Mask>$e164Mask</e164Mask>
                     <dirn>   
                        <pattern>$extension</pattern>
                        <routePartitionName>#####</routePartitionName>
                     </dirn>
                  </line>
               </lines>
            </phone>
      </ns:addPhone>
   </soapenv:Body>
</soapenv:Envelope>
"@


##### HERE BE DRAGONS....

# using postman, getLine API returns the same UUID as the DIRN UUID on the getPhone API.  However we need the LINE UUID.  Get this by grabbing the parent attribute for the DIRN UUID in the getPhone API.
# I dont get it either.... 


### Other XPATH queries Yonder for mapping UUIDs (universally unique identifier) to ID the correct line specific info on phone.
# The DIRN uuid matches up with the uuid for the line 
# Gets UUIDS for line and dirn elements:
$XPATH_DIRNUUID = $API_RequestLine.SelectNodes("//return/line/@*") | select -expand '#text'
$XPATH_LineUUID =  $API_RequestPhone.SelectNodes("//return/phone/lines/line/dirn[@uuid=""$XPATH_DIRNUUID""]/parent::*/@*") | select -Expand '#text'

# set line associations on phone:
$XPATH_PhoneDisplay = $API_RequestPhone.SelectNodes("//return/phone/lines/line[@uuid=""$XPATH_LineUUID""]/display") | select -Expand '#text'
$XPATH_PhoneDisplayAscii = $API_RequestPhone.SelectNodes("//return/phone/lines/line[@uuid=""$XPATH_LineUUID""]/displayAscii") | select -Expand '#text'
$XPATH_PhoneDisplayLabel = $API_RequestPhone.SelectNodes("//return/phone/lines/line[@uuid=""$XPATH_LineUUID""]/label") | select -Expand '#text'


# Get entire 'Lines' section of requestPhone XML
$LINE_XML = Select-Xml -Xml $API_RequestPhone -XPath $XPATH_LineConfig -Namespace $namespace  | select -Expand 'Node' | select -Expand 'InnerXml'





### Folks will need the "Standard AXL Access" (or something like that) role assigned in CUCM for this to work.


Write-Host ""
Write-Host ""
Write-Host ""
Write-Host "User Profile to be updated:  $userID  -  $callerID"
Write-Host "Caller ID to be updated:  $callerID"
Write-Host "Jabber Device to be created: $jabber"
Write-Host "Phones to be updated:  `n $associatedDevicesPurdy" 
Write-Host "The Phone Label will Read: $firstName $lastInitial.  $extension"
Write-Host "The Phone Description (for Admin purposes) will read:  $fullDescription"
Write-Host ""
Write-Host ""
Write-Host ""


$confirmPhone = Read-Host "Please select 'Y' to proceed or any other key to cancel"
switch($ConfirmPhone){
    Y{
        ### Hold my beer...

        ### ADD CSF device.  Should just error out if already there.  
            Invoke-RestMethod -Method Post -Uri "https://#.#.#.#:8443/axl/" -Headers $headers -Body $addCSF
            Write-Host "Creating Jabber Device...`n"
            Start-Sleep -Milliseconds 1000  # Give CUCM time to create device

        ### SET LINE DESCRIPTION  / ALETRING NAME / ASCII ALERTING NAME  TO $callerID 
            Invoke-RestMethod -Method Post -Uri "https://#.#.#.#:8443/axl/" -Headers $headers -Body $updateLine               

        ### Update Phone Description and owner User ID
            Invoke-RestMethod -Method Post -Uri "https://#.#.#.#:8443/axl/" -Headers $headers -Body $updatePhoneDescription
            
        ### GRAB LINE ASSOCIATED DEVICES AGAIN IN CASE CSF WAS ADDED.
            [xml]$API_RequestLine = Invoke-RestMethod -Method Post -Uri "https://#.#.#.#:8443/axl/" -Headers $headers -Body $lineRequest -Credential $creds 
            $associatedDevicesUpload = Select-Xml -Xml $API_RequestLine -XPath $XPATH_LineAssociatedDevices -Namespace $namespace | foreach {"<device>"+$_.Node.InnerXml+"</device>"} 

         ### ADD PHONE ASSOCIATION TO USER PROFILE
$updateUserDevices=@"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/11.5">
    <soapenv:Header/>
    <soapenv:Body>
        <ns:updateUser>
            <userid>$userID</userid>
            <associatedDevices>
                $associatedDevicesUpload
            </associatedDevices>
        </ns:updateUser>
    </soapenv:Body>
</soapenv:Envelope>
"@

             Invoke-RestMethod -Method Post -Uri "https://#.#.#.#:8443/axl/" -Headers $headers -Body $updateUserDevices -Credential $creds



        ### Update End-User Page
            Invoke-RestMethod -Method Post -Uri "https://#.#.#.#:8443/axl/" -Headers $headers -Body $updateUser



        <###
        ### 1. Grab line uuid from 'getLine' API.  This matches the 'dirn' uuid from the 'getPhone' request.
        ### 2. get parent *attribute* for dirn uuid.  use parent attribute to query the correct line element for the user.
        ### 2.5  Store Line uuid as PS Variable. 
        ### 3. Xpath line uuid to grab index, display, ascii display, and label.  
        ### 4. store Xpath result into PS variable ($LINE_XML).
        ### 5. use LINE_XML.replace() method to swap out result with new caller ID  
        ### X. do this for each phone in the $associatedDevicesPurdy list.
        ###>


         [xml]$API_RequestLine = Invoke-RestMethod -Method Post -Uri "https://#.#.#.#:8443/axl/" -Headers $headers -Body $lineRequest -Credential $creds
         $associatedDevicesPurdy = @(Select-Xml -Xml $API_RequestLine -XPath $XPATH_LineAssociatedDevices -Namespace $namespace | foreach {$_.Node.InnerXml})

         for ($i=0; $i -lt ($associatedDevicesPurdy.length); $i++) 
            {
                # Set Phone Name we are working with.  Grab from associated devices array.
                $associatedDevicesPurdy = @(Select-Xml -Xml $API_RequestLine -XPath $XPATH_LineAssociatedDevices -Namespace $namespace | foreach {$_.Node.InnerXml})   #refresh associated devices for CSF add
                $phone = $associatedDevicesPurdy[$i]
                Write-Host "Applying config to:`n $phone"

                #refresh GET API / $LINE_XML for current phone.   If you odnt do this, every phone associated will have same config as the Primary Phone.  Sorry Craig...
                $phoneRequest= @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/11.5">
    <soapenv:Header/>
    <soapenv:Body>
        <ns:getPhone>
            <name>$phone</name>
        </ns:getPhone>
    </soapenv:Body>
</soapenv:Envelope>
"@


                [xml]$API_RequestPhone = Invoke-RestMethod -Method Post -Uri "https://#.#.#.#:8443/axl/" -Headers $headers -Body $phoneRequest -Credential $creds

                $LINE_XML = Select-Xml -Xml $API_RequestPhone -XPath $XPATH_LineConfig -Namespace $namespace  | select -Expand 'Node' | select -Expand 'InnerXml'

                # Gets DIRN UUID for that phone --> line association
                $XPATH_DIRNUUID = $API_RequestLine.SelectNodes("//return/line/@*") | select -expand '#text'

                # Gets 'LINE UUID' FROM 'DIRN UUID' by getting attribute from parent element in XML.
                $XPATH_LineUUID =  $API_RequestPhone.SelectNodes("//return/phone/lines/line/dirn[@uuid=""$XPATH_DIRNUUID""]/parent::*/@*") | select -Expand '#text'



                # get Labels and junk for that line association.
                $XPATH_PhoneDisplay = $API_RequestPhone.SelectNodes("//return/phone/lines/line[@uuid=""$XPATH_LineUUID""]/display") | select -Expand '#text'
                $XPATH_PhoneDisplayAscii = $API_RequestPhone.SelectNodes("//return/phone/lines/line[@uuid=""$XPATH_LineUUID""]/displayAscii") | select -Expand '#text'
                $XPATH_PhoneDisplayLabel = $API_RequestPhone.SelectNodes("//return/phone/lines/line[@uuid=""$XPATH_LineUUID""]/label")  | select -Expand '#text'
                $XPATH_LineIndex = $API_RequestPhone.SelectNodes("//return/phone/lines/line[@uuid=""$XPATH_LineUUID""]/index") | select -Expand '#text'   # FYI:  TCT / BOT devices dont have labels.  Took me 2 days to figure out why it was erroring out here.   I are smart...
                $XPATH_LineE164 = $API_RequestPhone.SelectNodes("//return/phone/lines/line[@uuid=""$XPATH_LineUUID""]/e164Mask") | select -Expand '#text'


                $LINE_XML = $LINE_XML.replace($XPATH_PhoneDisplayLabel,"$firstName $lastInitial.  $extension" )
			    $LINE_XML = $LINE_XML.replace($XPATH_PhoneDisplay,$callerID)
			    $LINE_XML = $LINE_XML.replace($XPATH_PhoneDisplayAscii,$callerID)



                # Refresh $updatePhone with new vars before API call.

$updatePhone= @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/11.5">
   <soapenv:Header/>
      <soapenv:Body>
         <ns:updatePhone>
            <name>$phone</name>
            <lines>$LINE_XML</lines>
      </ns:updatePhone>
   </soapenv:Body>
</soapenv:Envelope>
"@

                Invoke-RestMethod -Method Post -Uri "https://#.#.#.#:8443/axl/" -Headers $headers -Body $updatePhone -Credential $creds

             } ### End Label update FOR loop 




    

    } ### End of Switch Case 'Y' Block


    default{
        ### Nope...  Nevermind... Done goofed.


     }### End of DEFAULT CASE

}



