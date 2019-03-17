DROP TABLE IF EXISTS `fromLines`;
CREATE /*temporary*/ TABLE fromLines(`from` int, `to` int, line varchar(255));
#insert into call_forwarding values(732,888); #add circle forwarding,more interesting
delimiter //
DROP PROCEDURE IF EXISTS pSearchCycles;
/*Making destination-numbers line for all forwarding numbers until first repeating*/
CREATE PROCEDURE pSearchCycles()
BEGIN
 SET SQL_SAFE_UPDATES=0;
 insert into fromLines(`from`,`to`,line) select `from`,`to`,concat('{',`from`,'}{',`to`,'}') from call_forwarding;
 WHILE (ROW_COUNT()>0) DO
	UPDATE fromLines f
	 INNER JOIN call_forwarding fwd ON fwd.from=f.to
        SET  f.to=fwd.to,
	     f.line=concat(line,'{',case when instr(f.line,concat('{',fwd.to,'}'))>0 then '|' else fwd.to end,'}')    
     WHERE  instr(f.line,'{|}')=0; /* and f.line>'' instead of slq_safe_updates=0, but work unstable*/
 END WHILE;
 SET SQL_SAFE_UPDATES=1;
END; //
delimiter ;
call pSearchCycles;
#SELECT f.from,f.line FROM fromLines f where `from` = `to`; #for debug

DROP TABLE IF EXISTS `grantednums`;
CREATE /*temporary*/ TABLE grantednums(number int, primary key(number));

delimiter //
DROP PROCEDURE IF EXISTS pGrantedForwarding;
CREATE PROCEDURE pGrantedForwarding()
BEGIN
 SET SQL_SAFE_UPDATES=0;
  INSERT INTO grantednums(number) 
   SELECT n.phone_number FROM numbers n                #inserting direct numbers without forwarding
    LEFT JOIN call_forwarding fwd ON fwd.from=n.phone_number
	 WHERE isnull(fwd.from)
   UNION
   SELECT `from` FROM fromLines where `from`=`to`;     #inserting wrong(cycled) numbers

/*Any forwarding which not added and which references on any granted numbers - is granted forwarding*/
 WHILE (ROW_COUNT()>0) DO
	INSERT INTO grantedNums(number) 
    SELECT nfwd.from FROM grantedNums g   
     INNER JOIN (select fwd.from,fwd.to from call_forwarding fwd 
				left join grantedNums gnm on gnm.number=fwd.from where isnull(gnm.number) ) nfwd 
     ON nfwd.to=g.number;
 END WHILE;
 SET SQL_SAFE_UPDATES=1;
END; //
delimiter ;

call pGrantedForwarding; 
#select * from grantedNums; #debug


############ 1. Total expences ####################################################################
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
SELECT (select DATE_FORMAT(min(Timestamp_start),'%d.%m.%y %H:%i') from call_logs limit 1) `start`,
       (select DATE_FORMAT(max(Timestamp_end),'%d.%m.%y %H:%i') from call_logs   limit 1) `end`,
       round(sum(CEILING((time_to_sec(cl.Timestamp_end)-time_to_sec(cl.Timestamp_start))/60))
		 *(select money from rates where id=3) ,2) `total expences` FROM call_logs cl
  LEFT JOIN grantedNums gn ON gn.number=cl.to
WHERE cl.call_dir='out' and isnull(gn.number);
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

########### 2. Top 10: Most active users ##########################################################
DROP TABLE IF EXISTS `commonActivities`;
CREATE TABLE commonActivities(rate int not null primary key auto_increment,name varchar(255),ia float,oa float,il float, ol float);
SET @k1=10,@k2=10,@k3=0.01,@k4=0.01;
INSERT INTO commonActivities(name,ia,oa,il,ol)
	SELECT concat(accs.name,'(UID:',accs.UID,')'),ifnull(ia.val,0),ifnull(oa.val,0),
								ifnull(il.val,0),ifnull(ol.val,0) FROM accounts accs 
		LEFT JOIN (SELECT UID,count(call_id) `val` FROM call_logs WHERE call_dir='in' GROUP BY UID) ia ON ia.UID=accs.UID
		LEFT JOIN (SELECT UID,count(call_id) `val` FROM call_logs WHERE call_dir='out' GROUP BY UID) oa ON oa.UID=accs.UID
		LEFT JOIN (SELECT UID,sum(time_to_sec(Timestamp_end)-time_to_sec(Timestamp_start)) `val` FROM call_logs WHERE call_dir='in' GROUP BY UID) il ON il.UID=accs.UID
		LEFT JOIN (SELECT UID,sum(time_to_sec(Timestamp_end)-time_to_sec(Timestamp_start)) `val` FROM call_logs WHERE call_dir='out' GROUP BY UID) ol ON ol.UID=accs.UID
        ORDER BY ia.val*@k1+oa.val*@k2+il.val*@k3+ol.val*@k4 DESC;
SELECT rate,name,ia `input calls`,oa `output calls`,il `input calls(sec)`,ol `output calls(sec)`,
	round(ia*@k1+oa*@k2+il*@k3+ol*@k4,2) `common activiti score` FROM commonActivities LIMIT 10;

########## 3. Top 10: Users with highest charges, and daily distribution for each of them #########
DROP TABLE IF EXISTS `highestcharges`;
CREATE TABLE highestcharges(rate int not null primary key auto_increment,name varchar(255),expences float);
INSERT INTO highestcharges(name,expences)
	SELECT concat(accs.name,'(UID:',accs.UID,')'),
 	 round(sum(CEILING((time_to_sec(cl.Timestamp_end)-time_to_sec(cl.Timestamp_start))/60))
	 *(select money from rates where id=3) ,2) `expences` FROM call_logs cl
	INNER JOIN accounts accs ON accs.UID=cl.UID
	LEFT JOIN grantedNums gn ON gn.number=cl.to
	WHERE cl.call_dir='out' and isnull(gn.number)
	GROUP BY accs.name ORDER BY  `expences` DESC
	LIMIT 10;
SELECT * FROM highestcharges;
