use test_yang

 

 

declare @StartDate date = case when datepart(weekday,getdate())=2 then  cast(DATEADD(week, DATEDIFF(day, 0, getdate())/7, 0)-7 as date) --casts start date to last monday if today is monday

else cast(DATEADD(week, DATEDIFF(day, 0, getdate())/7, 0) as date) end

declare @EndDate date = cast(getdate()-1 as date) -- end date is always yesterday

DECLARE @monthstart date = cast(DATEADD(m, datediff(m, 0, GETDATE()),0) as date) 

Declare @60daysago date =  cast(getdate()-60 as date)

Declare @30daysago date =  cast(getdate()-30 as date)

 

 

 

--THIS MONTH RefiPlus // Pull Appraisal Orders/Funds for programs within that department since month start for each AE in Refi Department

if object_id('tempdb..#ThisMonth') is not null drop table #ThisMonth

SELECT b.FstNm + ' ' + b.LstNm accountexec, WaterFallDivision, AE_EmpID

, sum(case when fundeddate >=@monthstart then 1 else 0 end) [FundedMo]

, sum(case when ApprOrdDate>=@monthstart then 1 else 0 end) [AOMo]

into #ThisMonth

from reports_ls_dm.dbo.[Secondary] (nolock) a

join topDownAELookupTable (nolock) b on a.AE_EmpID = b.Employee_Code

where

(UWProgramNm like '%yr co%' or UWProgramNm like '%yr rt%')

and WaterFallDivision like '%plus%'

group by b.FstNm + ' ' + b.LstNm, AE_EmpID,WaterFallDivision

 

 

 

 

--THIS MONTH Other //Catches any Appraisal Orders/Funds for programs not designated to RefiP;us department.
--AEs that transfered from other departments will have these loan types still in their pipeline

if object_id('tempdb..#ThisMonthOther') is not null drop table #ThisMonthOther

SELECT b.FstNm + ' ' + b.LstNm accountexec, AE_EmpID

, sum(case when fundeddate >=@monthstart then 1 else 0 end) [Funded CountOther]

, sum(case when ApprOrdDate>=@monthstart then 1 else 0 end) [AO CountOther]

into #ThisMonthOther

from reports_ls_dm.dbo.[Secondary] (nolock) a

join topDownAELookupTable (nolock) b on a.AE_EmpID = b.Employee_Code

where

(UWProgramNm not like '%yr co%' and UWProgramNm not like '%yr rt%')

group by b.FstNm + ' ' + b.LstNm, AE_EmpID

 

--PreIP Close Pullthrough RefiPlus 
--// Takes early pipline action (PreIP) within 30 day window 60 days ago. Counts funds from all loans with preIP action in that window to demo
--calc pullthrough conversion rate


select a.Employee_Code,

sum(case when b.PreInProcessDtm is not null then 1 else 0 end) [PreIP2mo]

,sum(case when c.FundedDate is not null then 1 else 0 end) [FundedSince]

into #fundpreip

from TEST_YANG..topDownAELookupTable (nolock) a

left join reports_ls_dm.dbo.[Secondary] (nolock) b on a.Employee_Code = b.AE_EmpID

left join reports_ls_dm.dbo.[Secondary] (nolock) c on a.Employee_Code = c.AE_EmpID and b.LoanNum = c.LoanNum

where b.PreInProcessDtm >= @60daysago

and b.PreInProcessDtm <= @30daysago

and a.WaterFallDivision like '%plus%'

and (b.UWProgramNm like '%yr co%' or  b.UWProgramNm like '%yr rt%')

group by a.Employee_Code

 

--PreIP Close Pullthrough Other 
--// just like last block of code but for loan programs designated for the department the AE is currently in(due to old pipline carrying over during department transfer)

select a.Employee_Code,

sum(case when b.PreInProcessDtm is not null then 1 else 0 end) [PreIP2moOther]

,sum(case when c.FundedDate is not null then 1 else 0 end) [FundedSinceOther]

into #fundpreipother

from TEST_YANG..topDownAELookupTable (nolock) a

left join reports_ls_dm.dbo.[Secondary] (nolock) b on a.Employee_Code = b.AE_EmpID

left join reports_ls_dm.dbo.[Secondary] (nolock) c on a.Employee_Code = c.AE_EmpID and b.LoanNum = c.LoanNum

where b.PreInProcessDtm >= @60daysago

and b.PreInProcessDtm <= @30daysago

and a.WaterFallDivision like '%plus%'

and (b.UWProgramNm not like '%yr co%' and  b.UWProgramNm not like '%yr rt%')

group by a.Employee_Code

 

 

--number of loans in pipe
--counts loans that have not had an ending action imposed on it 

if object_id('tempdb..#Pipeline') is not null drop table #Pipeline

select b.FstNm + ' ' + b.LstNm accountexec, AE_EmpID

, isnull(count(distinct applicationdtm),0) 'Pipeline Loans' -- counts the distinct timestamp for each time an app was taken.

into #Pipeline

from reports_ls_dm.dbo.[Secondary] (nolock) a

join topDownAELookupTable (nolock) b on a.AE_EmpID = b.Employee_Code

where (denieddate is null and InProcessDate is not null and fundeddate is null and withdrawndt is null and RescindedDtm is null)

and AE_EmpID is not null

and (UWProgramNm like '%yr co%' or UWProgramNm like '%yr rt%')

group by b.FstNm + ' ' + b.LstNm, AE_EmpID

 

 

--counting eventnames
--Takes a snapshot of lead aquisition actions/pipeline actions during the week (last week if today is monday)

if object_id('tempdb..#LeadsAndLoans') is not null drop table #LeadsAndLoans

select a.FstNm + ' ' + a.LstNm [AE Name], a.Employee_Code, a.WaterFallDivision, a.Team_Desc

 

, sum(case when eventname in ('web lead','transfer in') and MarketingChannel = 'web' then 1

                                                when eventname = 'transfer out' and MarketingChannel = 'web' then -1 else 0 end) [Net Web Leads]

, sum(case when eventname in ('router call','transfer in') and MarketingChannel != 'web' then 1

                                                when eventname = 'transfer out' and MarketingChannel != 'web' then -1 else 0 end) [Net Router Leads]

, sum(case when eventname = 'credit pull' then 1 else 0 end) [Open]

, sum(case when eventname = 'pitch'  then 1 else 0 end) [Pitches] --and ProductCat in ('cash out','rate&term')

, sum(case when eventname = 'appraisal order'  then 1 --and VAFHA in ('va','fha') and ProductCat in ('cash out','rate&term')

                                                when eventname = 'initial scrub cleared'  then 1 --and VAFHA = 'conv' and ProductCat in ('cash out','rate&term')

                                                else 0 end) [AOs]

into #LeadsAndLoans

from topDownAELookupTable (nolock) a

left join aeperformancereport_2 (nolock) b on a.Employee_Code = b.Employee_Code

--and eventname in ('router call','web lead','transfer in','transfer out','pitch','appraisal order','initial scrub cleared','credit pull')

and [date] >= @StartDate

and [Date] <= @EndDate

where a.ActiveCd = 'y'

and a.WaterFallDivision like 'refi plus%'

group by a.FstNm + ' ' + a.LstNm, a.Employee_Code, a.WaterFallDivision, a.Team_Desc

 

 

 

 

 

----PHONE ACTIVITY CALC----

 

--Phone Activity
--Pulls phone KPIs from raw data table

if object_id('tempdb..#Phone') is not null drop table #Phone

select [Name], c.Employee_Code, MidnightStartDate, AgentReporting --id for AE

, isnull(AgentEventOutboundCount,0) Outbounds

, isnull(b.TotalTalk_sec, 0) TalkTime

into #Phone

from test_yang.dbo.topDownAELookupTable (nolock) c 

left join testdb.dbo.agentperformance_mitel (nolock) a on c.mitelextension = a.agentreporting -- raw data table showing phone activity

and a.MidnightStartDate >= @StartDate

and a.MidnightStartDate <= @EndDate

left join test_yang.dbo.AE_IdleTalkTime (nolock) b on a.MidnightStartDate = b.[date] and a.AgentReporting = b.reporting -- this pivot table was created to agg Idle time/talk time per AE

where activecd = 'y'

and c.WaterFallDivision like 'refi plus%'

 

 

--DEDUP PHONE
--takes last record from temp table created since raw phone table does not overwrite 
-

;with cte as

(

select RN = row_number()over(partition by [name], agentreporting, midnightstartdate order by outbounds desc)

, *

from #Phone

)

delete cte where RN > 1

 

 

 

--Aggegating Phone Info

if object_id('tempdb..#AggPhone') is not null drop table #AggPhone

select [Name], Employee_Code

, sum(Outbounds) Outbounds

, sum(TalkTime) TalkTime

into #AggPhone

from #Phone

group by [Name], Employee_Code

 

 

 

----END OF PHONE ACTIVITY CALC

 

 

--Counts times customer wants to opt out in a given week


if object_id('tempdb..#VOO') is not null drop table #VOO

select AE_EmpID, count(*) VOO

into #VOO

from REPORTS_LS_DM.dbo.secondary (nolock) a

where (UWProgramNm like '%yr co%' or UWProgramNm like '%yr rt%')

and isnull(a.RescindedDtm, a.WithDrawnDt) >= @StartDate

and isnull(a.RescindedDtm, a.WithDrawnDt) <= @EndDate

and isnull(a.RescindedDtm, a.WithDrawnDt) >  a.ApprovedDate

and isnull(a.RescindedDtm, a.WithDrawnDt) is not null

group by AE_EmpID

 

 

--Headcount
--Takes headcount for each team by counting AEs that seeing if they took a lead anytime in the week or anytime since last monday if today is monday

Select

Team_Desc, count(distinct b.userid) Headcount

into #headcount

from TEST_YANG..topDownAELookupTable(nolock) a

left join TEST_YANG..AEPerformanceReport_2 (nolock) b on a.UserId = b.UserID

where a.WaterFallDivision like '%plus%'

and a.ActiveCd = 'y'

and cast(EventDate as date) >= case when datepart(weekday,getdate())=2 then  cast(DATEADD(week, DATEDIFF(day, 0, getdate())/7, 0)-7 as date)

else cast(DATEADD(week, DATEDIFF(day, 0, getdate())/7, 0) as date) end

and (eventname = 'router call' or eventname = 'web lead')

group by Team_Desc

 

 

 

 

 

-------EXPECTATION CALCULATIONS

 

--Robust Expectation Calculator
--Takes expectations set by managers and multiplies them by the percentage of the month/week we have completed. ie if it is the 15th of a 30 day month 
-- and the expectaion for closes is 10, then .5*10 is 5 expected closes at tht point in the month.

select division,expectation

, [Close]*(cast((cast(datediff(DD,DATEADD(month, DATEDIFF(month, 0, getdate()), 0),getdate())as float))/(cast(DAY(DATEADD(DD,-1,DATEADD(mm, DATEDIFF(mm, 0, GETDATE()) + 1, 0)))as float)) as decimal(3,2))) as [CloseExp]

, [AOMonth]* (cast((cast(datediff(DD,DATEADD(month, DATEDIFF(month, 0, getdate()), 0),getdate())as float))/(cast(DAY(DATEADD(DD,-1,DATEADD(mm, DATEDIFF(mm, 0, GETDATE()) + 1, 0)))as float)) as decimal(3,2))) as [AOMonthExp]

, [AOWeek]* (

case when datepart(weekday,getdate())=2 then  7

else DATEPART(weekday, getdate()-1) end

/7.00)  as [AOWeekExp]

into #exp

from test_yang..REFIPLUS_EXPECTATIONS1

 

 

 

 

 

-----FUNDSMONTH
--The managers intiially set 3 levels that impact AE comp: Minimum, Expectation, and Goal. 
--To easily metricize these levels I applied a numeric score from -1 to 2

select *

,case when b.expectation = 'Goal' and [FundedMo] >= [CloseExp] then 2

when  b.expectation = 'Expectation' and [FundedMo] >= [CloseExp] then 1

when b.expectation = 'Minimum' and [FundedMo] >= [CloseExp] then 0

when b.Expectation = 'Minimum' and [FundedMo] < [CloseExp] then -1 end FundExpectation

into #FundsExp

from #ThisMonth a

left join #exp b on a.WaterFallDivision = b.division

 

--DELETE ALL NULLS

delete from #FundsExp where  FundExpectation is null

 

 

--Keep Max from FundsExp
--When calculating funds epected, all values below the highest are recorded for each AE, to keep the true value, we must delete all lower values with the over and partition by clauses
;with cte as

(

select RN = row_number()over(partition by AE_EmpID order by FundExpectation desc)

, *

from #FundsExp

)

delete cte where RN > 1

 


 

----AOMONTH
--

select *

 

,case when b.expectation = 'Goal' and [AOmo] >= [AOMonthExp] then 2

when  b.expectation = 'Expectation' and [AOmo] >= [AOMonthExp] then 1

when b.expectation = 'Minimum' and [AOmo] >= [AOMonthExp] then 0

when b.Expectation = 'Minimum' and [AOmo] <[AOMonthExp]  then -1 end AOMonthExpectation

into #AOMonthExp

from #ThisMonth a

left join #exp b on a.WaterFallDivision = b.division

 

--Keep Max from AOMonth

delete from #AOMonthExp where  AOMonthExpectation is null

 

--Keep Max from AOMonth

;with cte as

(

select RN = row_number()over(partition by AE_EmpID order by AOMonthExpectation desc)

, *

from #AOMonthExp

)

delete cte where RN > 1

 

 

 

-------AOWEEK

select *

,case when b.expectation = 'Goal' and [AOs] >= b.AOWeekExp then 2

when  b.expectation = 'Expectation' and [AOs] >= b.AOWeekExp then 1

when b.expectation = 'Minimum' and [AOs] >= b.AOWeekExp then 0

when b.Expectation = 'Minimum' and [AOs] <b.AOWeekExp  then -1 end AOWeekExpectation

into #AOweek

from  #LeadsAndLoans a

left join #exp b on a.WaterFallDivision = b.division

 

 

--Keep Max from AOWeek

delete from #AOweek where  AOWeekExpectation is null

 

--Keep Max from AOWeek

;with cte as

(

select RN = row_number()over(partition by Employee_Code order by AOWeekExpectation desc)

, *

from #AOweek

)

delete cte where RN > 1

 

 

 

 

-------END OF CALCULATIONS----

 

 

 

--Bring It all Together
--Aggregates all AE Phone/Pipline KPIs and Expectation scores calculated above
--Tank the teams in using the headcount and Expectation scores to load into PowerBI

select a.*

, isnull(b.Outbounds,0) Outbounds

, isnull(cast((b.TalkTime /3600.00) as Decimal(10,1)) ,0) TalkTime

, isnull(v.[VOO],0) [VOO]

, isnull(c.[Pipeline Loans],0) [Current Pipe]

, isnull(d.AOMo, 0 ) [AOmo]

, isnull(d.FundedMo, 0 ) [FundedMo]

, isnull(e.Headcount, 0 ) [Headcount]

 

,i.PreIP2mo

,i.FundedSince

 

,j.PreIP2moOther

,j.FundedSinceOther

 

 

, f.CloseExp CurrentFundExpMonth

, f.FundExpectation FundExpectationPoints

, f.Expectation FundExpReached

 

 

, g.AOMonthExp CurrentAOExpMonth

, g.AOMonthExpectation AOMonthExpectationPoints

, g.Expectation AOMoExpReached

 

 

,h.AOWeekExp CurrentAOExpWeek

,h.AOWeekExpectation AOWeekExpectationPoints

,h.Expectation AOWeekExpReached

 

--into #final

from #LeadsAndLoans a

left join #AggPhone b on a.Employee_Code = b.Employee_Code

left join #Pipeline c on a.Employee_Code = c.AE_EmpID

left join #ThisMonth d on a.Employee_Code = d.AE_EmpID

left join #VOO v on a.Employee_Code = v.AE_EmpID

left join #headcount e on a.Team_Desc = e.Team_Desc

left join #FundsExp f on a.Employee_Code = f.AE_EmpID

left join #AOMonthExp g on a.Employee_Code = g.AE_EmpID

left join #AOweek h on a.Employee_Code = h.Employee_Code

left join #fundpreip i on a.Employee_Code = i.Employee_Code

left join #fundpreipother j on a.Employee_Code = j.Employee_Code

where a.Employee_Code not in ('a27x')

and a.WaterFallDivision not like '%avp%'

and a.WaterFallDivision not like '%rookie%'

order by Team_Desc, [AE Name], Employee_Code

 

--Select * from #final

--order by Team_Desc, [AE Name]

 

 

 

--drop table #final

drop table #exp

drop table #FundsExp

drop table #AOMonthExp

drop table #AOweek

drop table #ThisMonth

drop table #headcount

drop table #ThisMonthOther

drop table #fundpreip

drop table #fundpreipother
