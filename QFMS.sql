-- tables
-- Table: Allotment
CREATE TABLE Allotment (
    Passenger_Pid bigint NOT NULL,
    Quarantine_Center_Room_Number int NOT NULL,
    Allotment_Date date NOT NULL,
    CONSTRAINT Allotment_pk PRIMARY KEY (Passenger_Pid)
);

-- Table: Discharged
CREATE TABLE Discharged (
    Passenger_Pid bigint NOT NULL,
    Quarantine_Center_Room_Number int NOT NULL,
    Allotment_date int NOT NULL,
    Leaving_Date date NOT NULL,
    CONSTRAINT Discharged_pk PRIMARY KEY (Passenger_Pid)
);


-- Table: Passenger
CREATE TABLE Passenger (
    Pid bigint NOT NULL,
    Name varchar(50) NOT NULL,
    DOB date NOT NULL,
    Age int,
    Source_city varchar(50) NOT NULL,
    Source_state varchar(50) NOT NULL,
    Destination_city varchar(50) NOT NULL,
    Destination_state varchar(50) NOT NULL,
    Address varchar(255) NOT NULL,
    CONSTRAINT Passenger_pk PRIMARY KEY (Pid)
);

-- Table: Passenger_mobile
CREATE TABLE Passenger_mobile (
    Mobile_number bigint NOT NULL,
    Passenger_Pid bigint NOT NULL,
    CONSTRAINT Passenger_mobile_pk PRIMARY KEY (Mobile_number)
);

-- Table: Quarantine_Center
CREATE TABLE Quarantine_Center (
    Room_Number int NOT NULL,
    Hostel_Number int NOT NULL,
    Floor_Number int NOT NULL,
    Allotment_Status varchar(15) NOT NULL,
    CONSTRAINT Quarantine_Center_pk PRIMARY KEY (Room_Number)
);

-- foreign keys
-- Reference: Dischaged_Quarantine_Center (table: Discharged)
ALTER TABLE Discharged ADD CONSTRAINT Dischaged_Quarantine_Center FOREIGN KEY Dischaged_Quarantine_Center (Quarantine_Center_Room_Number)
    REFERENCES Quarantine_Center (Room_Number);

-- Reference: Discharged_Passenger (table: Discharged)
ALTER TABLE Discharged ADD CONSTRAINT Discharged_Passenger FOREIGN KEY Discharged_Passenger (Passenger_Pid)
    REFERENCES Passenger (Pid);

ALTER TABLE Allotment
DROP CONSTRAINT Room_Allotment_Passenger;

-- Reference: Person_mobile_Passenger (table: Passenger_mobile)
ALTER TABLE Passenger_mobile ADD CONSTRAINT Person_mobile_Passenger FOREIGN KEY Person_mobile_Passenger (Passenger_Pid)
    REFERENCES Passenger (Pid);

-- Reference: Room_Allotment_Passenger (table: Allotment)
ALTER TABLE Allotment ADD CONSTRAINT Room_Allotment_Passenger FOREIGN KEY Room_Allotment_Passenger (Passenger_Pid)
    REFERENCES Passenger (Pid);

-- Reference: Room_Allotment_Quarantine_Center (table: Allotment)
ALTER TABLE Allotment ADD CONSTRAINT Room_Allotment_Quarantine_Center FOREIGN KEY Room_Allotment_Quarantine_Center (Quarantine_Center_Room_Number)
    REFERENCES Quarantine_Center (Room_Number);

-- End of file.

-- Filling the derive attribute Age

delimiter $$
create trigger fillAge
before insert
on passenger
for each row
begin
	set new.age = round(datediff(curdate(), new.DOB)/365);
end $$
delimiter ;


-- Room allotment based on passenger details

delimiter $$
create trigger allot_room
after insert
on passenger
for each row
begin
	declare room_no INT;
    
	if new.age < 40 then
		select room_number into room_no from quarantine_center
        where allotment_status = 'vacant' and floor_number = 2
        limit 1;
	elseif new.age >= 40 and new.age < 60 then
		select room_number into room_no from quarantine_center
        where allotment_status = 'vacant' and floor_number = 1
        limit 1;
	else
		select room_number into room_no from quarantine_center
        where allotment_status = 'vacant' and floor_number = 0
        limit 1;
	end if;
    
    if room_no is not NULL then
		update quarantine_center
		set allotment_status = 'occupied'
		where room_number = room_no;
		
		insert into allotment (passenger_pid, quarantine_center_room_number, allotment_date)
		values (new.pid, room_no, curdate());
	end if;
end $$
delimiter ;

-- Stored procedure 
delimiter $$
create procedure getDischarged()
begin
	
end $$
delimiter ;

select a.passenger_pid, p.name, p.age, a.quarantine_center_room_number, a.allotment_date, date_add(a.allotment_date, interval 1 day) as 'Expected_discharge_date' from allotment a
inner join passenger p
on p.pid = a.Passenger_Pid
where round(datediff(curdate(), allotment_date)) >= 1;

delimiter $$
create procedure check_for_release()
begin
	insert into discharged(passenger_pid, quarantine_center_room_number, allotment_date, leaving_date)
    select Passenger_Pid, Quarantine_Center_Room_Number, Allotment_Date, curdate() from allotment
	where round(datediff(curdate(), allotment_date)) >= 14;
    
    update quarantine_center
    set allotment_status = 'vacant'
    where room_number = 
		(select Quarantine_Center_Room_Number from allotment
		where round(datediff(curdate(), allotment_date)) = 14);
    
    delete from allotment
	where round(datediff(curdate(), allotment_date)) = 14;
end $$
delimiter ;

call check_for_release();

drop procedure check_for_release;
-- schema for the summary table

create table available_rooms (
	id int primary key not null,
	floor_0 int,
    floor_1 int,
    floor_2 int 
);
alter table available_rooms max_rows=1;

-- Trigger to update the summary table when allotment is done

delimiter $$
create trigger update_vacancy
after insert
on allotment
for each row
begin
	declare f, f0, f1, f2, rownum int;
    select count(*) into rownum from available_rooms;
    
    set f0 = 0, f1 = 0, f2 = 0;
	select floor_number into f from quarantine_center 
    where room_number = new.quarantine_center_room_number;
    
	if f = 0 then
		set f0 = 1;
	elseif f = 1 then
		set f1 = 1;
	else 
		set f2 = 1;
	end if;
    
    if rownum = 0 then
		insert into available_rooms(id, floor_0, floor_1, floor_2)
        values (1, 200 - f0, 200 - f1, 100 - f2);
	else
		update available_rooms
        set floor_0 = floor_0 - f0,
			floor_1 = floor_1 - f1,
			floor_2 = floor_2 - f2
		where id = 1;
	end if;
end $$
delimiter ;

-- Trigger to update summary table when discharged

delimiter $$
create trigger update_vacancy_discharge
after insert
on discharged
for each row
begin
	declare f, f0, f1, f2, rownum int;
    
    set f0 = 0, f1 = 0, f2 = 0;
	select floor_number into f from quarantine_center 
    where room_number = new.quarantine_center_room_number;
    
	if f = 0 then
		set f0 = 1;
	elseif f = 1 then
		set f1 = 1;
	else 
		set f2 = 1;
	end if;
    
	update available_rooms
	set floor_0 = floor_0 + f0,
		floor_1 = floor_1 + f1,
		floor_2 = floor_2 + f2
	where id = 1;
end $$
delimiter ;

truncate available_rooms;

-- **********************************************************************************************************************
