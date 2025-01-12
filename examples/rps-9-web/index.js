import React from 'react';
import AppViews from './views/AppViews';
import DeployerViews from './views/DeployerViews';
import AttacherViews from './views/AttacherViews';
import {renderDOM, renderView} from './views/render';
import './index.css';
import * as backend from './build/index.main.mjs';
import { loadStdlib } from '@reach-sh/stdlib';
const reach = loadStdlib(process.env);

const handToInt = {'ROCK': 0, 'PAPER': 1, 'SCISSORS': 2};
const intToOutcome = ['Bob wins!', 'Draw!', 'Alice wins!'];
const {standardUnit} = reach;
const defaults = {defaultFundAmt: '10', defaultWager: '3', standardUnit};

function App() {
  const [view, setView] = useState('ConnectAccount');
  const [acc, setAcc] = useState(null);
  const [bal, setBal] = useState(null);
  const [ctcInfoStr, setCtcInfoStr] = useState(null);
  const [wager, setWager] = useState(null);
  const [outcome, setOutcome] = useState(null);
  const [hand, setHand] = useState(null);
  const [ContentView, setContentView] = useState(null);
  const [playable, setPlayable] = useState(false);

  useEffect(() => {
    (async () => {
      const acc = await reach.getDefaultAccount();
      const balAtomic = await reach.balanceOf(acc);
      const bal = reach.formatCurrency(balAtomic, 4);
      setAcc(acc);
      setBal(bal);
      if (await reach.canFundFromFaucet()) {
        setView('FundAccount');
      } else {
        setView('DeployerOrAttacher');
      }
    })();
  }, []);

  const fundAccount = async (fundAmount) => {
    await reach.fundFromFaucet(acc, reach.parseCurrency(fundAmount));
    setView('DeployerOrAttacher');
  }

  const skipFundAccount = () => { setView('DeployerOrAttacher'); }

  const selectAttacher = () => { setContentView(Attacher); setView('Wrapper'); }

  const selectDeployer = () => { setContentView(Deployer); setView('Wrapper'); }

  const random = () => { return reach.hasRandom.random(); }

  const getHand = async () => { // Fun([], UInt)
    const hand = await new Promise(resolveHandP => {
      setView('GetHand');
      setPlayable(true);
      setHand(null);
      setOutcome(null);
      setHand(null);
      setHand(null);
      setContentView(() => (
        <GetHand
          random={random}
          playHand={playHand}
          resolveHandP={resolveHandP}
        />
      ));
    });
    setView('WaitingForResults');
    setHand(hand);
    return handToInt[hand];
  }

  const playHand = (hand) => { resolveHandP(hand); }

  const seeOutcome = (i) => { setView('Done'); setOutcome(intToOutcome[i]); }

  const informTimeout = () => { setView('Timeout'); }

  const acceptWager = async (wagerAtomic) => { // Fun([UInt], Null)
    const wager = reach.formatCurrency(wagerAtomic, 4);
    return await new Promise(resolveAcceptedP => {
      setView('AcceptTerms');
      setWager(wager);
      setOutcome(null);
      setHand(null);
      setHand(null);
      setContentView(() => (
        <AcceptTerms
          wager={wager}
          acceptTerms={acceptTerms}
          resolveAcceptedP={resolveAcceptedP}
        />
      ));
    });
  }

  const acceptTerms = () => {
    resolveAcceptedP();
    setView('WaitingForTurn');
  }

  const deploy = async () => {
    const ctc = acc.contract(backend);
    setView('Deploying');
    setWager(null);
    setOutcome(null);
    setHand(null);
    setHand(null);
    setCtcInfoStr(null);
    setContentView(() => (
      <Deploy
        ctc={ctc}
        deploy={deploy}
        setWager={setWager}
        setView={setView}
      />
    ));
    const wager = reach.parseCurrency(wager); // UInt
    const deadline = {ETH: 10, ALGO: 100, CFX: 1000}[reach.connector]; // UInt
    backend.Alice(ctc, {getHand, seeOutcome, acceptWager, informTimeout});
    const ctcInfoStr = JSON.stringify(await ctc.getInfo(), null, 2);
    setCtcInfoStr(ctcInfoStr);
    setView('WaitingForAttacher');
  } 
