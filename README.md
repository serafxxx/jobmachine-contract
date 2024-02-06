JobMachine
How machines/DAO/people hire people. 
Use smart contracts to hire and get things done.
API friendly way to create smart contracts between customers and contractors.
Dispute resolution

The idea is to provide a smart contract which defines interactions between customer and contractor, carefully describing and guaranteeing rights and duties of parties. Smart contracts could use other smart contracts in their logics.
Another critical idea is to provide flexible API to make integrations easy. 

Such contracts could be a great way to build relationships between parties for both tiny and huge things. Tiny things are possible because of integrations, for example integration with project management system which will create a contract for each task.

To run tests

```
cd jobmachine-contract
forge test
```
To mint contract
```
forge create --rpc-url https://goerli.infura.io/v3/<ID> --private-key <PK> src/JobMachine.sol:JobMachine
```

To call a function of the minted contract 
```angular2html
cast send <ContractAddress> "setJobMintFee(uint)" 1000000000000000 --rpc-url=https://goerli.infura.io/v3/<ID> --private-key <PK>
```

**Description is pretty outdated**

General
1. **Skill** - represents different skills of contractor, like expertise in some area, his location, ownership of something (some equipment), opportunity to do something etc. Abilities used to filter contractors and allow access to tasks. Abilities come from contracts (Customer will set abilities needed for the contract). Once Contractor finished job successfully, those abilities will show up in their profile. Ability has a title and rating. Ratings counted based on contracts finished (contracts number and rewards). If you are as a contractor will finish the contract, your abilities list will update based on which skills were set in the contract. Skill set by Customer for the job:
    1. Title
    2. Weight for the job
    3. Type
2. **Dispute rating** - counted based on the rule: each contract transition will add positive or negative impact to the person's rating. Add positive impact if user's answer was among those who won. So to constantly increase your judgement rating you need to give same answer as majority (and the only way to keep increasing constantly is to give an answer which makes most sense). If somebody will be giving random answers than their rating wouldn't grow over the time. So the best judges are those who's rating constantly grow during the recent period of time.
3. **Dispute process** - reserve way for the Contractor to move job to Success state  
    

Сontract Properties
1. Owner - customer, contractor or parity.
    1. If owner is Contractor: once started, contractor work on the task, providing a result in defined structure (json object). Could include abilities and deadline restrictions. Nobody judges the result. Contract is finished and reward goes to the contractor after they provided their result. Result could be used to count contractor's rating on something. Could be used to do votes, polls, etc.
    2. If owner is Customer: Contractor see the description, signup for the contract, do the job and provide the result. Customer reviews and either finishes the contract or returning back to work. Nothing could force customer to accept the work and thus finish contract and release reward. Could be used inside organization for simplicity when parties trust each other.
    3. If no owner (parity) then: while contract is in working state, one party could offer to move to finished state and another party could agree or disagree. If parties come to the point where they don't agree, they could call for the third (independent) party. In this case contract automatically creates sibling ContractorsPower contracts (uneven amount of contracts with same abilities) and promote those contracts to random persons from the web directory. The judge rating would be updated using the judgement score rule.
2. Customer - could be a person, a DAO, another contract or anything else.
3. Contractor
4. Skills - A list of restrictions for the parties. For example, if contractor abilities set to python programmer then only those who has that ability could apply.
5. Body - the description of task or other information needed for Contractor
6. Reward - to be paid to the Contractor upon successful execution
7. Deadline - amount of seconds allowed for the Contractor to do the task
8. Deadline fine - to be paid by contractor in case of failed deadline
9. Review deadline - time allowed for Customer for review 
10. Owner - the one who created contract. Owner could change contract after creation, while contract in Initial state.
11. Result structure - definition of the structure of result (json) so that it could easily be picked up and used by other contracts/algorithms/integrations. Contract couldn't be finished if provided result structure do not match.
12. Judgement reward - reward to set should the judgement process start
13. Judgement contracts amount - uneven amount of contracts to create

Contract could be created by any side.

Contract has a number of states and a defined flow to go from one state to another. Some base states are: initial, working, review, transition, finished, failed, cancelled.

Access rights. The existence of the contract couldn't be hidden as its in the block chain. But fields could be hidden. For example, contract's title and short description could be public while contract body (the description of the task) could be hidden until approved by owner or open for contractors with some abilities. 

Some fields of the contract could be optionally hidden and revealed upon matching some criteria (abilities) or upon owner's approval.

Hey Siri ask somebody to cut my lawn.

Картинка с вендинговой машиной которая заполняет контракты, хранит свитки и деньги.

That could be a way to freeze money for somebody until some event happen with a way to resolve dispute. Like investment into something but only when something else happen (I'll give you money once you'll get first 100 users)

How it Works

There are three roles in each job
* Owner - the creator/manger of the job until job starts.
* Customer
* Contractor
Anyone could take more than one role.

Minting the Job
Anyone could mint a new job and become its owner. Mint fee is applied to avoid numerous empty contracts. Upon minting job enters Initial state. All contract parameters could be passed at once upon minting or changed during the Initial state.
Owner should set customer and contractor among other parameters. So if you're a customer and you created a job (meaning you're an owner), you should set a contractor.

Signing
Once listed in the job, Customer and Contractor could sign it to express their willing to participate in the job. Owner could change the job, but it will cancel all signatures and parties have to sign again. Although there are some fields that could be changed without discarding signatures (for example, no need to discard Customer's signature after changing or setting Contractor)

Funding
At any time during the initial state anybody could fund any balances of the job (Reward, DeadlineFine, etc). During initial state funder could withdraw their balances back or owner could refund funder. Some restrictions apply:
* You can fund when balance is zero or when you're a funder of existing balance. In other words, only one funder allowed for the balance. This rule introduced because we want to be able to refund but refunding to multiple funders seems complicated. 
* Its possible to initiate refund of any amount of the balance by funder or by owner. Money will go back to the funder.

Contractors, open/closed jobs
There are two ways how Contractor could be set for the job. By default owner should set the contractor. But there is a way to make job open and allow contractor to apply without confirmation. If Customer will sign the job and Contractor will be unset then anybody could do an applyAsContractor call (deadlineFine fee should be funded simultaneously). Opened job is a signed by Customer job with empty Contractor.

Moving on to the Work state
Owner could start off the job by transitioning its state from Initial to Work. For the transition to succeed, the Customer and Contractor should be set and signed, Reward and Deadline funds should be in place. If all requirements met, contract will transition to the Work state, meaning job is now locked.

Timers
There are some timers available on the job. Timers attached to the state and measures time spent in one state, so not more than one timer is running at a time. For example, if Work timer is running - all other timers are paused. Job updates timers each time tick function called. Timers are running down from its current state to zero. Owner could enable timer during Initialization state (by setting to greater than zero) or could leave timers disabled (with zero value) meaning they will never fire.
* Work timer - is a deadline for Contractor. Use it to make sure Contractor wouldn't work forever. Once counted down to zero, job will transition to Failed state, reward and deadlineFine funds would be released to Customer. Timer will start counting down while job is in Work state. No way to increase value of that timer after transition from Init state.
* Review timer - maximum time Customer could spend for Review. Needed for the Contractor to make sure review wouldn't span forever. Timer would be reset automatically each time job enters Review state.

Failed Job
Job could fail if deadline timer will run out. Deadline timer ticks while job is in working state (timer would be paused if job will transition to different state).

Enable Review
If Customer should confirm moving to Success.
During the initial state, owner could enable Review flag. Enable Review flag introduces two types of jobs. If review is disabled, then its perfectly possible for the Contractor to transition job from Work to Success state in any time and unconditionally. Meaning Contractor could release reward to himself  unconditionally. That type of interaction is needed for some automation tasks and probably is not interesting for interactions between two real people.
If review is forced by the flag then Contractor could transition from Work state to Review state. Work timer would be paused, Review timer will run (if was enabled during initialization state). Its now Customer's time to review job done. Contractor have two options here: if not satisfied then transition back to Work state (asking to continue to work) or transition forward to Success state and releasing reward to Contractor. Meaning only Customer could decide to release reward to Contractor (unless timer runs out).
Contractor could transition from Work to Review. Customer could transition from Review back Work or forward to Success. Also shortcut from Work directly to Success is available for Customer.

Enable Dispute Resolution
Dispute resolution is a reserve way for Contractor to move job to Success. Dispute resolution job should be paid by contractor. Once jobs minted, they would be offered to random reviewers. Dispute job will include a link to parent job and reviewers will decide based on parent job metadata, transitions and Customer/Contractor comments.
There is no Dispute state for the job, meaning job will stay in Work state during the dispute and all time spent for the dispute is counted towards the deadline.
 
1. Contractor changes state from Work to Dispute and provides their input on the matter.
2. Customer will have 3 days (by default) to provide their input.
3. All input and link to the job will go to the review job description. Reviewer could access job and see its description and see the input from customer and contractor in review job description.
4. Once Customer provided input or timer flows out, Contractor could initiate the process by sending the review jobs initiate request along with money and amount of review jobs they want to mint (uneven and at least 3).
5. Jobs for the reviewers minted. Reward comes from Contractor. Abilities are copied from the main job, type of the abilities  Review ability is added.
6. Jobs for the reviewers minted How to assign reviewers?. Current job is taking the owner and customer roles for minted jobs (the job, not the person).


Contract should somehow decide which reviewers to invite to the job. Just randomly pick users with reviewer ability and other abilities matching the job..



---
В контракте участвуют три стороны: заказчик, разработчик и независимый ревьювер (представитель компании разработавшей смарт-контракт)
Входы контракта: Хеш описания работы, сумма за разработку, дедлайн (кол-во секунд до сдачи) , штраф за нарушение дедлайна и хеш пароля для разработчика, время отведенное на проверку/исправление
1. Заказчик делает листинг с описанием работы и входными параметрами. Листинг возможно менять до момента заключения контракта.
2. Разработчик договаривается с заказчиком о цене и штрафах, заполняет все входные параметры для контракта
3. Когда найден разработчик который готов взяться за работы и все входные параметры согласованы - заказчик активирует контракт и сумма за разработку блокируется контрактом. 
4. Пароль разработчика перезадется разработчику и разработчик переводит переводит сумму штрафов на контракт. С этого момента контракт заключен, в нем участвуют три стороны. После заключения контракта третьей стороне перечисляется плата за пользование контрактом.
5. Листинг с описанием работы после заключения контракта изменить нельзя (дополнительная работа соласовывается через новые контракты).
6. Разработчик передает работу заказчику. Таймер дедлайна останавливается и запускается таймер проверки результата.
7. Заказчик может либо принять работу либо вернуть. Если работа принята то контракт считается исполненым. Плата за разработку перечисляется разработчику, заблокированные средства для штрафа за дедлайн возвращается разработчику.
8. Если заказчик не предпринимает действий в течении времени проверки то контракт автоматически закрывается и считается выполненным
9. Если заказчик возвращает работу на доработку то разработчик может либо принять сторону заказчика и начать исправлять замечания (таймер дедлайна продолжит тикать) либо может не согласиться.
10. Контракт может содержать множество точек состояния в которых требуется принятие решения. Решения принимаются множеством голосов, причем незвисимая сторона голосует последней. Таким образом третья сторона используется для разрешения противоречий и перевода котракта в следующий стейт. Каждое голосование третьей стороны оплачивается из средств контракта.

---

- Разные типы контрактов которые можно создавать программно. Контракты могут использовать другие контракты в своих алгоритмах работы
- Контракт "Голосование" - выясняет мнение исполнителя (только одного исполнителя). Если надо выяснить мнение 1000 разработчиков то создается тасяча контрактов с экспертизой "разработчик". Результат голосования можно автоматически использовать в другом контракте.
- Пазл - контракт который можно использовать для реализации суда присяжных. Требует ответа контрактора и потом дает свой верный ответ. В случае верного ответа рейтинг контрактора в этой области повышается. Так можно выявить тех кто чаще принимает верные решения.
- Контракт типа "заказчик главный" - заказчик решает когда работа выполнена верно. Однако это не означает полную безответственность заказчика. Например, вводится срок на ревью, в течении которого если не дан ответ то контракт закрывается и так далее. Регулирование отношений имеет место в любом контракте
- Контракт "включающий третью независимую сторону". Контракт между заказчиком и подрядчиком с возможностью разрешать споры с помощью независимой стороны (независимой стороной может являться большая группа людей обладающая нужной экспертизой). Для реализации третьей стороны используется контракты-пазлы (верным ответ для пазла считается ответ большинства) либо контракты-голосование. 
- Контрак типа Тендер - который принимает ставки и выбирается самая маленькая ставка или взвешивается с уровнем экспертизы и так контракт сам нанимает подрядчика
- Доступ к контрактам можно получить либо на прямую через блокчейн, либо через апи, либо через портал.
- Создатель контракта управляет доступом к контракту (видимость, возможность заключить контракт и тд)
- Контракты можно группировать, например создается контракт для проекта в целом, где возможно описываются высокоуровневые вешчи и под ним (как в папке) создаются другие контракты описывающие более мелкие работы. Например, высокуровнеый контракт может описывать факт приема разработчика на работу и некие права/обязанности, а мелкие контракты это ежедневные задачи
- Пользователи могут обладать экспертизой в некоей области. Экспертиза может быть подтверждена несколькими способами. Возможность подписать некий контракт может зависить от экспертизы в некоей области (настраевается в момент создания контракта). Экспертизой может быть не только навык но и что-то еще, например доступ к ресурсу, либо местонахождение
- Возможность реализовывать реально сложные проекты. Например проект открытой машины. Под это делается DAO, инвестируется начальный капитал. Проводится голосование, согласовываются требования. Затем нанимаются люди для продумывания и реализации различных частей машины, при этом проводятся тендеры и так далее
- Библиотека определений - шаблонов описания сути задачи в контракте. Например, определение "качественного программного кода на языке Питон". Заказчик может использовать эти термины и ссылаться на определения, возможно добавляя некоторые переопределения. Исполнители, ознакимившись один раз с определением, будут понимать о чем речь. У заказчиков появляется инструмент, с помощью которого они могут предоставить довольно четкое описание довольно простыми методами. Например, "протестировать сайт на популярных браузерах" означает "проверка следующего списка параметров для вот этого списка браузеров таких-то версий".
- Почасовой контракт (преподаватель)
- Контракты работают в обе стороны - заказчик может создать контракт с пустым местом для заказчика
