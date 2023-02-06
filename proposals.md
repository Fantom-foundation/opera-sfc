## Gas monetization
Идея заключается в том, чтобы перераспределить часть сжигаемой комиссии за транзакцию между популярными dapps  на  Fantom.
https://docs.fantom.foundation/funding/gas-monetization
Сейчас это реализовано как отправка 10% комиссии на адрес treasury,  который управляется черз governance стейкерами.
Мы предлагаем сделать возможность установить пару **target - recipient** таким образом, чтобы определенный процент комисии от транзакции с target адреса шел recepient'у.
Предполагается уменьшить процент сжигаемых токенов до 5%, и использовать для распределения высвободившиеся 15%, таким образом награда для валидаторов останется неизменной.
Для этого нужно будет решить следующие проблемы:

1. сейчас комиссия распределяется в функции **sealEpoch** контракта **SFC.sol**, нода шлет кол-во валидаторов и снэпшот эпохи в котором указывается кол-во собранной комиссии и далее она внутри цикла распределяется между каждым валидатором за вычетом процента на сжигание и treasury fee, которая шлется в treasury в конце.
Здесь невозможно адресно распределить процент для recepient'ов так как у нас нет информации кто осуществлял эти транзакции.
2. Не все транзакции будут от target'ов, комисии полученные от адресов не участвующих в программе будут отправлены на мультисиг кошелек и использоваться для поддержки экосистемы Fantom.

### Решение
Храним пару target - recipient в виде mapping'а в контракте SFC
```
mapping(address => address) public getRecipient;
```
Во время регистрации транзакции в go-opera в случае если она направлена на target мы увеличиваем balance recipient  на 15% от комиссии, если нет то увеличиваем баланс мультисиг кошелька.

Для этой фичи потребуется изменение в `StateTransition.TransitionDb` функцию, в конце функции нужно добавить код, который будет проверять были ли ошибки при вызове EVM, если ошибок не было, то будет проверка на то, есть зарегистрирован ли target контракт в базе данных SFC, если зарегистрирован, то часть `StateTransition.usedGas` пойдет на адрес recipient это адреса.

## Gas subsidies
Данная фича позволит пользователю совершать транзакции не имея при этом средств для оплаты газа. Желающие стать спонсорами регистрируют свой EOA в SFC контракте, где указывают EOA (nominee) за который они собирают платить, максимальное количество газа (опционально), контракт к которому обращается отправитель транзакции (опционально).
Когда nominee совершает транзакцию, за нее платит спонсор.

### Решение
Основано на предложении https://gist.github.com/ARX06/e74988749dd4749f8b8fc8926a342f82

В SFC либо в отдельном контракте храним следующие данные
```
struct Sponsor {
    address from;
    uint256 gasLimit;
    address dest;
}

//nominee => sponsors list
mapping(address => Sponsor[]) public sponsors; 

```
Чтобы стать спонсором пользователь вызывает функцию approve

```
function approve(address _nominee, uint256 _gasLimit, address _dest) public {
    sponsors[_nominee].push(
        Sponsor{
            from: msg.sender,
            gasLimit: _gasLimit,   //assume unlimited gas if 0
             dest: _dest           //assume any destination if zero address
        }
    );
}
```
Чтобы отозвать спонсорство пользователь вызывает функцию revoke
```
function revoke(address _nominee) public {
    //we omit realization of this function, we can write our own or use OZ enumerable set to manage sponsor list 
    removeSponsorFromArray(_nominee, msg.sender); 
}
```
Во время транзакции в go-opera мы обращаемся к контракту sfc.getSponsor(from, gasFees, to)

```
function getSponsor(address _nominee, uint256 _gasAmount, address _dest) public view returns(address) {
    Sponsor[] memory sponsorsList = sponsors[_nominee];
    for(uint256 i=0; i<sponsorList.length; i++) {
        // wrong dest
        if(sponsorsList[i].dest != address(0) && sponsorsList[i].dest != _dest)
            continue;
        // out of tokens
        if(sponsorsList[i].from.balance < _gasAmount)
            continue;
        // wrong amount
        if(sponsorsList[i].gasLimit < _gasAmount && sponsorsList[i].gasLimit !=0)
            continue;
        return sponsorsList[i]
    }
    return address(0);
}
```
метод возвращает адрес спонсора из баланса которого и вычитаются комиссии.

В `go-opera` потребуются изменения в `Message` структуру, туда добавится новое поле - `Sponsor`, который будет инициализироваться в `StateTransition.precheck` функции, беря спонсора из SFC контракта, если же спонсора нет, то он просто оставляет это поле непроинициализированным. Далее `buyGas` функция будет проверять это поле на null значение, если у него есть значение, то оплата за gas будет вычитаться с `Sponsor` EOA. Также потребуются изменения в `StateTransition.refundGas`, там также будет проверка, был ли оплачен gas с аккаунта спонсора, если же он был оплачен с аккаунта спонсора, то gas возвращается ему же.
