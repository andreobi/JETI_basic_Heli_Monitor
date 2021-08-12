--[[
This APP has the following tasks
1.	measure the BEC voltage
	give alarm if the voltage is lower the threshold for 0.6 seconds to filter spikes
	it is still recommanded to have a direct BEC alarm with a littelbit lower threshold
	
2.	measure the batterie voltage and current
	compensate the voltage drop caused by the current
	set alarm if the compensate voltage is lower than the threshold
	(Ubatt / NumberCell + Ibatt * Ri  < alUbat
	
3.  announce the used cpacity 20%, 40%, 60%, 75%

4.  monitor the rx signal quality and strength (always anounced as A1)

5.  monitor the rpm depending on the flight mode
	tollerate a rampup time and a hysterese of 15 rpm
	during the rampup the rpm has to grow at least by 1 rpm per main loop (~25ms)
		engine off	: rpm = 0				t= rampup + 10s
		autorotation: rpm = 0				t= rampup +  5s
		FM			: rmp = low, mid, high	t= rampup

	Abriviations
	al:		Alarm
	ch:		changed
	cur:	current
	id:		Index
	init:	Initialisation
	li:		List
	p:		Pointer
	par:	Parameter
	rep:	repeat
	sl:		selected
	
--]]
----------------------------------------------------------------------
-- Locals for the application
local appName ="Heli Monitor"
-- Selected Parameter
local rxBound
local alTimeSensor
local alSenText
local alUbec
local alUbat
local slAlPeriod
local slCellNum, slRi
local slIdUbat, slParUbat
local slIdIbat, slParIbat
local slAlFile
local slIdUbec, slParUbec
-- Filter Time in sec
local alTimeUbec, alSpikeUbec
local alTimeUbat, alSpikeUbatt
--capa
local slIdCapa, slParCapa
local slCapa
local capaTime
local alCntCapa
local capaLevel
-- RX monitoring
local alTimeRxs
local alTimeRxq
local pRxConf
local rxQRef
local rxRssiRef
local rssiConvert = {0, 2, 4, 7, 10, 13, 17, 21, 26, 32}
local rxQout
local rxRout
local rxDetected = {}
-- RPM monitor
local alTimeRpm
local slIdRpm, slParRpm
local slRpmTime
local swEngine, swAuto, swFmLow, swFmMid
local fmAlt
local fmTimeRef
local fmActive
local rpmRef
local rpmFm = {}		-- engine off, auto rot, rmp low, rpm mid, rpm high
local senRpmHys = 20	-- engine rampup drop
-- alarm flags
local alarm = {}

--
----------------------------------------------------------------------
-- Draw the main form (Application inteface)
local function initForm()
-- Pointer to Sensor in List 
local pLiUbat=0
local pLiIbat=0
local pLiUbec=0
local pLiCapa=0
local pLiRpm=0
-- Liste Sensor 
local liSenLab = {"..."}
local liSenId = {"..."}
local liSenPar = {"..."}

-- Read available sensors to select from
	local liSen = system.getSensors()
	for i,sensor in ipairs(liSen) do
		if (sensor.label ~= "") then
			table.insert(liSenLab, string.format("%s", sensor.label))
			table.insert(liSenId, string.format("%s", sensor.id))
			table.insert(liSenPar, string.format("%s", sensor.param))
		end
	end
-- init sensor pionters
	for i, p in ipairs(liSenPar) do
		if (p==slParUbat and liSenId[i]==slIdUbat) then
			pLiUbat=i
		end
		if (p==slParIbat and liSenId[i]==slIdIbat) then
			pLiIbat=i
		end
		if (p==slParUbec and liSenId[i]==slIdUbec) then
			pLiUbec=i
		end
		if (p==slParCapa and liSenId[i]==slIdCapa) then
			pLiCapa=i
		end
		if (p==slParRpm and liSenId[i]==slIdRpm) then
			pLiRpm=i
		end
	end
	
-- U-BEC Sensor
	form.addRow(2)
	form.addLabel({label="U-BEC sensor"})
	form.addSelectbox(liSenLab,pLiUbec,true,function(value)
		pLiUbec = value
		slIdUbec = string.format("%s", liSenId[value])
		slParUbec = string.format("%s", liSenPar[value])
		if (slIdUbec == "...") then
			slIdUbec = 0
			slParUbec = 0
		end
		system.pSave("slIdUbec", slIdUbec)
		system.pSave("slParUbec", slParUbec)
	end)

-- Alarm Voltage U-BEC
	form.addRow(2)
	form.addLabel({label="Alarm U-BEC min"})
	form.addIntbox(alUbec, 300, 840,770,2,1,function(value) alUbec=value; system.pSave("alUbec",value); end)

	-- U-Battery Sensor
	form.addRow(2)
	form.addLabel({label="U-Battery sensor"})
	form.addSelectbox(liSenLab,pLiUbat,true,function(value)
		pLiUbat = value
		slIdUbat = string.format("%s", liSenId[value])
		slParUbat = string.format("%s", liSenPar[value])
		if (slIdUbat == "...") then
			slIdUbat = 0
			slParUbat = 0
		end
		system.pSave("slIdUbat", slIdUbat)
		system.pSave("slParUbat", slParUbat)
		system.pSave("pLiUbat", pLiUbat)
	end)
	
-- I-Battery Sensor
	form.addRow(2)
	form.addLabel({label="I-Battery sensor"})
	form.addSelectbox(liSenLab,pLiIbat,true,function(value)
		pLiIbat=value
		slIdIbat = string.format("%s", liSenId[value])
		slParIbat = string.format("%s", liSenPar[value])
		if (slIdIbat == "...") then
			slIdIbat = 0
			slParIbat = 0
		end
		system.pSave("slIdIbat", slIdIbat)
		system.pSave("slParIbat", slParIbat)
	end)

--capa
	form.addRow(2)
	form.addLabel({label="Capacity sensor"})
	form.addSelectbox(liSenLab,pLiCapa,true,function(value)
		pLiCapa = value
		slIdCapa = string.format("%s", liSenId[value])
		slParCapa = string.format("%s", liSenPar[value])
		if (slIdCapa == "...") then
			slIdCapa = 0
			slParCapa = 0
		end
		system.pSave("slIdCapa", slIdCapa)
		system.pSave("slParCapa", slParCapa)
	end)
	form.addRow(2)
	form.addLabel({label="Akku Capacity"})
	form.addIntbox(slCapa, 10, 20000,5000,0,10,function(value) slCapa=value; system.pSave("slCapa",value); end)

-- Number of Cells
	form.addRow(2)
	form.addLabel({label="Number Cells"})
	form.addIntbox(slCellNum,1,20,6,0,1,function(value) slCellNum=value; system.pSave("slCellNum",value); end)

-- Total Battery Ri
	form.addRow(2)
	form.addLabel({label="Battery Ri /cell"})
	form.addIntbox(slRi,0,1000,25,1,1,function(value) slRi=value; system.pSave("slRi",value); end)

-- Alarm Voltage per Cell
	form.addRow(2)
	form.addLabel({label="Alarm Umin /cell"})
	form.addIntbox(alUbat, 290, 400,320,2,1,function(value) alUbat=value; system.pSave("alUbat",value); end)

-- Audio alarm File
	form.addRow(2)
	form.addLabel({label="selAudio"})
	form.addAudioFilebox(slAlFile,function(value) slAlFile=value; system.pSave("slAlFile",value); end)

-- number of secounds to repeat the alarn
	form.addRow(2)
	form.addLabel({label="Repeat Alarm"})
	form.addIntbox(slAlPeriod, 4, 60,8,0,1,function(value) slAlPeriod=value; system.pSave("slAlPeriod",value); end)
	
-- FM switches
	form.addRow(2)
	form.addLabel({label="SW: Engine Off"})
	form.addInputbox(swEngine,true, function(value) swEngine=value;system.pSave("swEngine",value); end ) 
	form.addRow(2)
	form.addLabel({label="SW: Autorotation"})
	form.addInputbox(swAuto,true, function(value) swAuto=value;system.pSave("swAuto",value); end ) 
	form.addRow(2)
	form.addLabel({label="SW: FM low RPM"})
	form.addInputbox(swFmLow,true, function(value) swFmLow=value;system.pSave("swFmLow",value); end ) 
	form.addRow(2)
	form.addLabel({label="SW: FM mid RPM"})
	form.addInputbox(swFmMid,true, function(value) swFmMid=value;system.pSave("swFmMid",value); end ) 

-- Rpm Sensor
	form.addRow(2)
	form.addLabel({label="RPM sensor"})
	form.addSelectbox(liSenLab,pLiRpm,true, function(value)
		pLiRpm=value
		slIdRpm = string.format("%s", liSenId[value])
		slParRpm = string.format("%s", liSenPar[value])
		if (slIdRpm == "...") then
			slIdRpm = 0
			slParRpm = 0
		end
		system.pSave("slIdRpm", slIdRpm)
		system.pSave("slParRpm", slParRpm)
		end)

--rpm rampup time
	form.addRow(2)
	form.addLabel({label="RPM time"})
	form.addIntbox(slRpmTime,1,20,0,0,1,function(value) slRpmTime=value; system.pSave("slRpmTime",value); end)

-- rpm alarm level
	form.addRow(2)
	form.addLabel({label="RPM low"})
	form.addIntbox(rpmFm[3],0,4000,1400,0,10, function(value) rpmFm[3]=value; system.pSave("rmpLow",value); end)
	form.addRow(2)
	form.addLabel({label="RPM mid"})
	form.addIntbox(rpmFm[4],0,4000,1800,0,10, function(value) rpmFm[4]=value; system.pSave("rmpMid",value); end)
	form.addRow(2)
	form.addLabel({label="RPM high"})
	form.addIntbox(rpmFm[5],0,4000,2300,0,10, function(value) rpmFm[5]=value; system.pSave("rmpHigh",value); end)

-- rx configuration
	form.addRow(2)
	form.addLabel({label="RX Quality"})
	form.addIntbox(rxQRef,0,100,70,0,1, function(value) rxQRef=value; system.pSave("rxQRef",value); end)
	local trssi = 9
	for i,v in pairs(rssiConvert) do
		if (rxRssiRef == v) then
			trssi = i-1
			break
		end
	end
	form.addRow(2)
	form.addLabel({label="RX Strength"})
	form.addIntbox(trssi,0,9,4,0,1, function(value) rxRssiRef=rssiConvert[value+1]; system.pSave("rxRssiRef",rxRssiRef); end)
	local liRxConf = {"RX1", "RX1, RX2", "RX1, RXB", "RX1, RX2, RXB"}
	form.addRow(2)
	form.addLabel({label="RX configuration"})
	form.addSelectbox(liRxConf,pRxConf,true,function(value) pRxConf=value; system.pSave("pRxConf",value); 
		rxDetected[1] = true
		rxDetected[2] = false
		rxDetected[3] = false
		rxBound = 0
		if (value == 2 or value == 4) then
			rxDetected[2] = true
		end
		if (value == 3 or value == 4) then
			rxDetected[3] = true
		end
	end)

end
----------------------------------------------------------------------
-- Runtime functions
local function loop()
	local curTime = system.getTimeCounter()
	alarm.sensor = false
	alSenText = ""

-- rx bound or timeout
	local txTel = system.getTxTelemetry ()
	for i= 1, 6 do
		if (txTel.RSSI[i] > 0) then
			rxBound = rxBound +1
			rxTimeout = 200
		end
	end
	if (rxTimeout > 0) then
		rxTimeout = rxTimeout -1
	else
		rxBound = 0
	end

	if (rxBound > 200) then

-- U-Batt/cell + ri * I
		local senUbat = system.getSensorByID(slIdUbat, slParUbat)
		local senIbat = system.getSensorByID(slIdIbat, slParIbat)
	
		if(senUbat and senIbat) then
			if(senUbat.valid and senIbat.valid) then
				if (senUbat.value / slCellNum + (senIbat.value * slRi) /10000 < alUbat/100) then
					if (curTime - alSpikeUbatt > 260) then
						alarm.ubat=true
					end
				else
					alSpikeUbatt = curTime
				end			
 			else
				alarm.sensor = true
				alSenText = alSenText .. "U - I  "
			end
		end

-- U-BEC or U-RX
		local senUbec = system.getSensorByID(slIdUbec, slParUbec)
		local calUbec = txTel.rx1Voltage

		if(senUbec) then
			if (senUbec.valid) then
				if (senUbec.value < calUbec) then
					calUbec = senUbec.value
				end
 			else 
				alarm.sensor = true
				alSenText = alSenText .. "Ubec  "
			end
		end
	
		if (calUbec < (alUbec/100)) then
			if (curTime - alSpikeUbec > 600) then
				alarm.ubec = true
			end
		else
			alSpikeUbec = curTime
		end

--Capa
		local senCapa = system.getSensorByID(slIdCapa, slParCapa)
		if(senCapa) then
			if (senCapa.valid) then
				if (senCapa.value > slCapa*0.75) then
					if (capaLevel < 5) then
						alCntCapa = 10
						capaLevel = 5
					end
				elseif (senCapa.value > slCapa*0.7) then
					if (capaLevel < 4) then
						alCntCapa = 4
						capaLevel = 4
					end
				elseif (senCapa.value > slCapa*0.6) then
					if (capaLevel < 3) then
						alCntCapa = 1
						capaLevel = 3
					end
				elseif (senCapa.value > slCapa*0.4) then
					if (capaLevel < 2) then
						alCntCapa = 1
						capaLevel = 2
					end
				elseif (senCapa.value > slCapa*0.2) then
					if (capaLevel < 1) then
						alCntCapa = 1
						capaLevel = 1
					end
				elseif (senCapa.value < slCapa*0.1) then
					if (capaLevel > 0) then
-- und Spannung + Ri * I > 4,1V Akku wirklich voll?
						capaLevel = 0
						alCntCapa = 0
					end
				end
			else
				alarm.sensor = true
				alSenText = alSenText .. "Capacity  "
			end
		end

-- RX signal quality
		alarm.rx_q = true
		alarm.rx_s = true
		if (txTel.rx1Percent >= rxQRef) then
			alarm.rx_q = false
		else
			rxQout = txTel.rx1Percent
		end	
		if (txTel.RSSI[1] >= rxRssiRef or txTel.RSSI[2] >= rxRssiRef) then
			alarm.rx_s = false
		else
			rxRout = math.max(txTel.RSSI[1], txTel.RSSI[2])
		end
		if (rxDetected[2]) then
			if (txTel.rx2Percent >= rxQRef) then
				alarm.rx_q = false
			else
				rxQout = math.max(rxQout, txTel.rx2Percent)
			end
			if (txTel.RSSI[3] >= rxRssiRef or txTel.RSSI[4] >= rxRssiRef) then
				alarm.rx_s = false
			else
				rxRout = math.max(rxRout, txTel.RSSI[3], txTel.RSSI[4])
			end
		end
		if (rxDetected[3]) then
			if (txTel.rxBPercent >= rxQRef) then
				alarm.rx_q = false
			else
				rxQout = math.max(rxQout, txTel.rxBPercent)
			end
			if (txTel.RSSI[5] >= rxRssiRef or txTel.RSSI[6] >= rxRssiRef) then
				alarm.rx_s = false
			else
				rxRout = math.max(rxRout, txTel.RSSI[5], txTel.RSSI[6])
			end
		end

-- RPM
		local enVal, autoVal, fmLow, fmMid = system.getInputsVal(swEngine, swAuto, swFmLow, swFmMid)
		local fm = 5
		if(enVal and enVal==1) then
			fm=1
			alarm.rpm = false
		elseif (autoVal and autoVal==1) then 
			fm=2
			alarm.rpm = false
		elseif(fmLow and fmLow==1) then 
			fm=3
		elseif (fmMid and fmMid==1) then 
			fm=4
		end

		local senrpm = system.getSensorByID(slIdRpm, slParRpm)
		if (senrpm) then
			if (senrpm.valid) then
				local senRpmLow = math.max(senrpm.value - senRpmHys, 0)
				if (fm ~= fmAlt) then
					if (senRpmLow >= rpmFm[fm]) then
						fmActive = true
						rpmRef = rpmFm[fm]
					else
						fmActive = false
						fmTimeRef = curTime
						if (fmAlt == 1) then
							fmTimeRef = fmTimeRef + 10000	-- additional 10s time to start after engine off
						elseif (fmAlt == 2) then
							fmTimeRef = fmTimeRef + 5000	-- additional 5s time to start after autorotation
						end
					end
				end
				if (not fmActive) then
					if (senRpmLow >= rpmFm[fm] or fmTimeRef + slRpmTime*1000 < curTime) then
						fmActive = true
						rpmRef = rpmFm[fm]
					else
						if (senrpm.value > rpmRef) then
							rpmRef = senrpm.value
						else 
							rpmRef = rpmRef + 0.5
						end
					end
				end
				if (senrpm.value + senRpmHys < rpmRef) then
					alarm.rpm = true
				end
			else
				alarm.sensor = true
				alSenText = alSenText .. "RPM"
			end
		end
		fmAlt = fm
		
-- prioritize alarm output and do timining 
		if (alarm.rpm) then
			alarm.rpm = false
			if (curTime - alTimeRpm >2000) then
				alTimeRpm = curTime
				system.playNumber(senrpm.value, 0, "", "Revolution")
				system.messageBox("low RPM",2)
			end
		elseif (alarm.rx_q) then
			alarm.rx_q = false
			if (curTime - alTimeRxq >2000) then
				alTimeRxq = curTime
				system.playNumber(rxQout, 0, "Q")
				system.messageBox("RX quality",2)
			end
		elseif (alarm.rx_s) then
			alarm.rx_s = false
			if (curTime - alTimeRxs >2000) then
				alTimeRxs = curTime
				local trssi = 9
				for i,v in pairs(rssiConvert) do
					if (rxRout < v) then
						trssi = i-2
						break
					end
				end
				system.playNumber(trssi, 0, "A1")
				system.messageBox("RX strength",2)
			end
		elseif (alarm.ubat) then
			alarm.ubat = false
			if (alTimeUbat < curTime) then
				alTimeUbat = curTime + slAlPeriod*1000
				if (slAlFile) then
					system.playFile(slAlFile,AUDIO_AUDIO_QUEUE)
				end
				system.playNumber ((senUbat.value / slCellNum), 2, "V")
				system.messageBox("UBatt Alarm",2)
			end
		elseif (alarm.ubec) then
			alarm.ubec = false
			if (alTimeUbec < curTime) then
				alTimeUbec = curTime + slAlPeriod*1000
				system.playNumber (calUbec, 2, "V")
				system.messageBox("U-BEC Alarm",2)
			end
		elseif (alCntCapa > 0) then
			if (capaTime < curTime) then
				capaTime = curTime + slAlPeriod*1000
				alCntCapa = alCntCapa -1
				system.playNumber (senCapa.value, 0, "mAh")
				if (alCntCapa > 0) then
					alCntCapa = alCntCapa -1
					system.messageBox("Capa",2)
				end
			end
		elseif (alarm.sensor) then
			if (curTime - alTimeSensor > slAlPeriod*1000) then
				alTimeSensor = curTime
				system.playNumber(-1, 0,"","SensErr")
				system.messageBox("SEN:  " .. alSenText,2)
			end		
		end

-- rx timeout
	else
		alCntCapa = 0
		capaLevel = 0
		alarm.ubat = false
		alarm.ubec = false
		alarm.rx_q = false
		alarm.rx_s = false
		alarm.rpm = false
	end
--
end
----------------------------------------------------------------------
-- Application initialization
local function init()
	system.registerForm(1,MENU_APPS,appName,initForm)

	slIdUbec = system.pLoad("slIdUbec",0)
	slParUbec = system.pLoad("slParUbec",0)
	alUbec = system.pLoad("alUbec",780)
	slIdUbat = system.pLoad("slIdUbat",0)
	slParUbat = system.pLoad("slParUbat",0)
	slIdIbat = system.pLoad("slIdIbat",0)
	slParIbat = system.pLoad("slParIbat",0)
	slIdRpm = system.pLoad("slIdRpm",0)
	slParRpm = system.pLoad("slParRpm",0)
	slRpmTime = system.pLoad("slRpmTime",6)
	swEngine = system.pLoad("swEngine")
	swAuto = system.pLoad("swAuto")
	swFmLow = system.pLoad("swFmLow")
	swFmMid = system.pLoad("swFmMid")
	rpmFm[1] = 0
	rpmFm[2] = 0
	rpmFm[3] = system.pLoad("rmpLow",0)
	rpmFm[4] = system.pLoad("rmpMid",0)
	rpmFm[5] = system.pLoad("rmpHigh",0)
	fmAlt = 0
	slCellNum = system.pLoad("slCellNum",6)
	slRi = system.pLoad("slRi",25)
	alUbat = system.pLoad("alUbat",365)
	slAlFile = system.pLoad("slAlFile",0)
	slAlPeriod = system.pLoad("slAlPeriod",12)
	slIdCapa = system.pLoad("slIdCapa",0)
	slParCapa = system.pLoad("slParCapa",0)
	slCapa = system.pLoad("slCapa",5000)
	rxQRef = system.pLoad("rxQRef",60)
	rxRssiRef = system.pLoad("rxRssiRef",7)
	pRxConf = system.pLoad("pRxConf",1)
	rxDetected[1] = true
	rxDetected[2] = false
	rxDetected[3] = false
	if (pRxConf == 2 or pRxConf == 4) then
		rxDetected[2] = true
	end
	if (pRxConf == 3 or pRxConf == 4) then
		rxDetected[3] = true
	end
	rxBound = 0
	rxTimeout = 200

	alTimeUbat = system.getTimeCounter()
	alSpikeUbatt = alTimeUbat
	alTimeUbec = alTimeUbat
	alSpikeUbec = alTimeUbat
	capaTime = alTimeUbat
	fmTimeRef = alTimeUbat
	alTimeRxs = alTimeUbat
	alTimeRxq = alTimeUbat
	alTimeRpm = alTimeUbat
	alTimeSensor = alTimeUbat

	alCntCapa = 0
	capaLevel = 0
	
	alarm.ubat = false
	alarm.ubec = false
	alarm.rx_q = false
	alarm.rx_s = false
	alarm.rpm = false
	
	fmActive = false
	rpmRef = 0
end
----------------------------------------------------------------------

return {init=init, loop=loop, author="Andre", version="2.17", name=appName}
