// The MacBook from the Assist webapp (Assistwebapp/dist): a Google Meet call on screen, with the
// Assist notch on top. Styles are the webapp's desktop styles, minus its CSS animations.
import React from "react";
import { Loop, OffthreadVideo, staticFile } from "remotion";
import { BODY, DISPLAY } from "../theme";

export const MB = {
  width: 1120,
  height: 662,
  screenX: 59,
  screenY: 9,
  screenW: 1002,
  screenH: 618,
};

const css = `
.mb{position:absolute;left:0;top:0;width:1120px;font-family:${BODY};color:#f5f6f8;-webkit-font-smoothing:antialiased}
.mb *{box-sizing:border-box}
.mb p,.mb h2{margin:0}
.mb-lid{width:1020px;margin:0 auto;padding:8px 8px 20px;border:1px solid #74777e;border-radius:23px 23px 10px 10px;background:linear-gradient(135deg,#3a3d43,#1d1f24 5%,#08090b 40%,#3b3c44);box-shadow:0 0 0 1px #141519,0 2px 0 2px #55586175,inset 0 1px 1px #ffffff7a,0 40px 100px #0008;position:relative}
.mb-screen{width:1002px;height:618px;position:relative;overflow:hidden;border-radius:15px 15px 2px 2px;background:radial-gradient(ellipse at 0 0,#45716b70,transparent 70%),radial-gradient(ellipse at 100% 100%,#6651769e,transparent 65%),linear-gradient(140deg,#172d31,#293145 48%,#32304c)}
.mb-screen-edge{position:absolute;inset:0;pointer-events:none;border-radius:inherit;box-shadow:inset 0 0 0 1px #ffffff16;z-index:60}
.mb-menubar{height:26px;padding:0 17px;color:#d6dae4;display:flex;align-items:center;justify-content:space-between;font-size:10px;background:#090e1730}
.mb-menubar>div{display:flex;gap:17px;align-items:center}
.mb-menubar b{font-weight:700}
.mb-meet{position:absolute;inset:38px 24px 40px;background:#17191d;border:1px solid #ffffff20;border-radius:9px;overflow:hidden;box-shadow:0 8px 20px #0004;display:flex;flex-direction:column}
.mb-toolbar{height:28px;display:flex;align-items:center;justify-content:space-between;padding:0 12px;background:#282a30;flex-shrink:0}
.mb-lights{display:flex;gap:5px}
.mb-lights i{width:7px;height:7px;border-radius:50%;background:#ff6058}
.mb-lights i:nth-child(2){background:#febc2e}
.mb-lights i:nth-child(3){background:#28c840}
.mb-address{height:18px;display:flex;align-items:center;justify-content:center;gap:6px;background:#151619;border:1px solid #ffffff08;border-radius:4px;width:52%;font-size:8px;color:#adb0b8}
.mb-topline{height:44px;display:flex;align-items:center;justify-content:space-between;padding:0 16px;flex-shrink:0}
.mb-brand{display:flex;align-items:center;gap:6px;font-size:11px;color:#d5d8df}
.mb-title{font-size:10px;color:#b3b7c1}
.mb-badge{font-size:8px;color:#838995;border:1px solid #ffffff15;border-radius:4px;padding:3px 5px;margin-left:7px}
.mb-timer{font-size:9px;color:#7f8591;font-variant-numeric:tabular-nums}
.mb-content{position:relative;display:grid;grid-template-columns:1.75fr 1fr;gap:9px;min-height:0;flex:1;padding:0 12px}
.mb-person{position:relative;overflow:hidden;background:#2a3235;border-radius:8px;isolation:isolate}
.mb-shade{position:absolute;inset:0;background:linear-gradient(transparent 45%,#070a0d9e)}
.mb-plabel{position:absolute;left:14px;bottom:12px;color:white;font-size:10px}
.mb-plabel>span{color:#ffffffaa}
.mb-talk{position:absolute;right:11px;top:11px;width:21px;height:21px;display:flex;align-items:center;justify-content:center;border-radius:50%;background:#407af4;gap:2px}
.mb-talk i{display:block;width:2px;border-radius:2px;background:white}
.mb-caption{position:absolute;bottom:40px;left:15px;right:15px;background:#0b1113c9;border:1px solid #ffffff1a;box-shadow:0 3px 10px #0002;border-radius:9px;padding:11px 13px;font-size:14px;line-height:1.45;min-height:64px;display:flex;flex-direction:column;justify-content:center}
.mb-caption>span{display:block;font-size:9px;color:#74ead2;margin-bottom:4px;font-weight:600}
.mb-side{display:grid;grid-template-rows:1fr 1.2fr;gap:9px;min-height:0}
.mb-self{position:relative;background:radial-gradient(ellipse at 70% 30%,#433847,#272833);border-radius:8px;display:flex;align-items:center;justify-content:center;min-height:0}
.mb-avatar{background:linear-gradient(140deg,#cbb1bf,#7b838f);box-shadow:0 4px 24px #0003,inset 0 1px 0 #ffffff60;color:#26202c;position:relative;height:59px;width:59px;border-radius:50%;display:grid;place-items:center;font-family:${DISPLAY};font-size:16px;font-weight:500}
.mb-ring{position:absolute;inset:-5px;border-radius:50%;border:2px solid #74ead2}
.mb-slabel{position:absolute;bottom:10px;left:12px;color:#e2dbe6;font-size:9px}
.mb-preview{border:1px solid #ffffff17;border-radius:8px;background:#dee7d9;color:#233e33;padding:17px 18px 11px;position:relative;overflow:hidden;display:flex;flex-direction:column;align-items:flex-start}
.mb-kicker{font-size:7px;letter-spacing:1.5px;font-weight:600}
.mb-preview strong{font-family:${DISPLAY};font-size:23px;line-height:1.06;letter-spacing:-.6px;margin-top:12px;font-weight:500;z-index:1}
.mb-mini{position:absolute;right:18px;top:30%;bottom:25px;display:flex;align-items:flex-end;gap:5px;width:40%;opacity:.7;transform:rotate(-12deg)}
.mb-mini i{width:18%;border-radius:4px 4px 0 0;background:linear-gradient(#6e9b83,#c5d5bc)}
.mb-pbottom{font-size:8px;margin-top:auto;padding-top:16px;display:flex;justify-content:space-between;width:100%}
.mb-controls{height:48px;display:flex;align-items:center;justify-content:space-between;padding:0 15px;flex-shrink:0}
.mb-callinfo{font-size:9px;color:#d6d8dd;display:flex;align-items:center;gap:8px}
.mb-callinfo i{height:13px;width:1px;background:#ffffff30}
.mb-icons{display:flex;gap:7px;align-items:center}
.mb-icons>span{width:29px;height:29px;border-radius:50%;background:#31343c;display:grid;place-items:center;color:#e7e9ee;font-size:10px}
.mb-icons svg{width:14px;height:14px;stroke:currentColor;fill:none;stroke-width:1.7;stroke-linejoin:round;stroke-linecap:round}
.mb-icons .mb-hang{background:#d84244;width:43px;border-radius:20px}
.mb-count{font-size:10px;color:#b9bec8}
.mb-dock{position:absolute;bottom:3px;left:50%;transform:translateX(-50%);display:flex;align-items:center;gap:7px;background:#ffffff12;border:1px solid #ffffff20;border-radius:9px;padding:3px 6px}
.mb-dock>span{width:24px;height:24px;border-radius:6px}
.mb-base{position:relative;width:1120px;height:16px;margin-top:-4px;border-radius:2px 2px 38% 38% / 2px 2px 95% 95%;background:linear-gradient(90deg,#4b4e54 0%,#9c9fa6 2%,#4e5058 9%,#71747b 15%,#73767e 85%,#46494f 95%,#878b91 99%,#282b31 100%);box-shadow:inset 0 1px 0 #c7c9d3,inset 0 -4px 3px #000b,0 2px 2px #000;z-index:3}
.mb-base>div{position:absolute;left:43%;top:0;width:14%;height:7px;background:linear-gradient(#383b43,#61646b);border-radius:0 0 9px 9px}
.mb-shadow{position:absolute;bottom:-17px;left:12%;width:76%;height:30px;background:#000;filter:blur(16px);z-index:-1}
.mb-deck{position:absolute;inset:0 12px;background:#e5ecdd;color:#294234;border-radius:8px;overflow:hidden;display:flex;flex-direction:column;padding:20px 26px 12px}
.mb-deck-top{display:flex;align-items:center;justify-content:space-between;flex-shrink:0}
.mb-logo{font-size:19px;font-family:${DISPLAY};letter-spacing:-1px;font-weight:600}
.mb-logo>span{font-size:16px;color:#538265;margin-left:2px}
.mb-deck-top>span:last-child{font-size:7px;letter-spacing:1.7px;color:#5d7562}
.mb-deck-main{flex:1;display:grid;grid-template-columns:1.5fr 1fr;align-items:center;gap:30px;min-height:0;padding-bottom:70px}
.mb-deck-main h2{font-family:${DISPLAY};font-size:40px;line-height:1.07;font-weight:500;letter-spacing:-1.5px;margin:9px 0}
.mb-deck-main h2 em{font-style:normal;color:#66836c}
.mb-deck-main p{font-size:10px;color:#718574;margin-bottom:16px}
.mb-metrics{display:flex;gap:30px}
.mb-metrics>div{display:flex;flex-direction:column;gap:2px}
.mb-metrics b{font-family:${DISPLAY};font-size:28px;font-weight:500;letter-spacing:-1px}
.mb-metrics span{font-size:8px;color:#617568}
.mb-chart{background:#ffffff25;border:1px solid #35573420;border-radius:12px;padding:15px;height:170px;position:relative}
.mb-chart-top{display:flex;justify-content:space-between;font-size:9px}
.mb-chart-top b{font-weight:500}
.mb-bars{display:flex;gap:12px;align-items:flex-end;height:calc(100% - 32px);padding-top:15px}
.mb-bars>span{width:20%;min-height:10px;border-radius:5px 5px 0 0;background:linear-gradient(#8caa7c,#ccdac0);font-size:7px;display:flex;justify-content:center;align-items:flex-end;padding-bottom:4px;color:#456441}
.mb-bars>span:last-child{background:linear-gradient(#55734d,#9bb98b)}
.mb-deck .mb-caption{left:22px;right:22px;bottom:14px;color:#f5f6f8}
.mb-ocr{border-radius:4px;padding:0 2px;margin:0 -2px}
`;

export type OcrHit = number; // 0..1 highlight strength

export type MeetState = {
  t: number;
  /** 0 = the call grid, 1 = Alex presenting the Bloom deck. */
  presenting: number;
  caption: { who: string; text: string } | null;
  youSpeaking: boolean;
  alexSpeaking: boolean;
  timer: string;
  dof: number;
  ocr: { headline: OcrHit; price: OcrHit; hours: OcrHit; question: OcrHit };
};

const ocrStyle = (k: number): React.CSSProperties =>
  k > 0.001
    ? { boxShadow: `0 0 0 ${1.5}px rgba(94,242,194,${0.95 * k}), 0 0 14px rgba(94,242,194,${0.45 * k})`, background: `rgba(94,242,194,${0.16 * k})` }
    : {};

const Talk: React.FC<{ t: number; on: boolean }> = ({ t, on }) => (
  <span className="mb-talk" style={{ opacity: on ? 1 : 0.0 }}>
    {[0, 1, 2].map((i) => (
      <i key={i} style={{ height: 4 + (on ? 7 * Math.abs(Math.sin(t * 9 + i * 1.3)) : 0) }} />
    ))}
  </span>
);

export const Meet: React.FC<MeetState> = ({ t, presenting, caption, youSpeaking, alexSpeaking, timer, dof, ocr }) => {
  const grid = 1 - presenting;
  return (
    <div className="mb-meet" style={{ filter: dof > 0.05 ? `blur(${dof}px)` : undefined }}>
      <div className="mb-toolbar">
        <div className="mb-lights">
          <i />
          <i />
          <i />
        </div>
        <div className="mb-address">
          <svg viewBox="0 0 20 20" width="10" height="10" fill="none" stroke="#959ba4" strokeWidth="1.3">
            <rect x="5" y="9" width="10" height="8" rx="2" />
            <path d="M7 9V6a3 3 0 0 1 6 0v3" />
          </svg>
          meet.google.com / your-next-big-thing
        </div>
        <span style={{ fontSize: 13, color: "#a2a6ae" }}>＋</span>
      </div>
      <div className="mb-topline">
        <span className="mb-brand">
          <svg viewBox="0 0 28 24" width="22" height="19">
            <path fill="#34a853" d="M2 5h17v17H2z" />
            <path fill="#4285f4" d="M2 5h7v17H2z" />
            <path fill="#fbbc04" d="m19 8 8-5v19l-8-5z" />
            <path fill="#ea4335" d="M2 5 7 0h12v5z" />
          </svg>
          <span>Google Meet</span>
        </span>
        <span className="mb-title">
          Your next big thing
          {presenting > 0.5 ? <span style={{ color: "#8c96a6" }}> · Alex is presenting</span> : <span className="mb-badge">Bloom × Northwind</span>}
        </span>
        <span className="mb-timer">{timer}</span>
      </div>
      <div className="mb-content">
        <div className="mb-person" style={{ opacity: grid }}>
          {/* OffthreadVideo pulls exact frames with ffmpeg, so none go missing in parallel renders. The clip is 15.1 s. */}
          <Loop durationInFrames={900} layout="none">
            <OffthreadVideo src={staticFile("call.mp4")} muted style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }} />
          </Loop>
          <div className="mb-shade" />
          <span className="mb-plabel">
            Alex Johnson <span>· Northwind</span>
          </span>
          <Talk t={t} on={alexSpeaking} />
          {caption && presenting < 0.5 ? (
            <div className="mb-caption">
              <span>{caption.who}</span>
              {caption.text}
            </div>
          ) : null}
        </div>
        <div className="mb-side" style={{ opacity: grid }}>
          <div className="mb-self">
            <div className="mb-avatar">
              You
              {youSpeaking ? <span className="mb-ring" style={{ opacity: 0.6 + 0.4 * Math.abs(Math.sin(t * 8)) }} /> : null}
            </div>
            <span className="mb-slabel">You</span>
          </div>
          <div className="mb-preview">
            <span className="mb-kicker">PITCH DECK / 03</span>
            <strong>
              Less busywork.
              <br />
              More possibility.
            </strong>
            <span className="mb-mini">
              {[20, 38, 55, 72, 100].map((h) => (
                <i key={h} style={{ height: `${h}%` }} />
              ))}
            </span>
            <span className="mb-pbottom">
              <span>Bloom · Q4 pitch</span>
              <span>⤢</span>
            </span>
          </div>
        </div>
        {presenting > 0.001 ? (
          <div className="mb-deck" style={{ opacity: presenting, transform: `scale(${0.96 + 0.04 * presenting})` }}>
            <div className="mb-deck-top">
              <span className="mb-logo">
                bloom<span>✳</span>
              </span>
              <span>THE OPPORTUNITY</span>
            </div>
            <div className="mb-deck-main">
              <div>
                <span className="mb-kicker">GIVE YOUR TEAM THEIR TIME BACK.</span>
                <h2>
                  <span className="mb-ocr" style={ocrStyle(ocr.headline)}>
                    Less busywork.
                    <br />
                    <em>More possibility.</em>
                  </span>
                </h2>
                <p>One workspace. Every follow-up, handled.</p>
                <div className="mb-metrics">
                  <div>
                    <b className="mb-ocr" style={ocrStyle(ocr.hours)}>
                      12h
                    </b>
                    <span>saved per person / week</span>
                  </div>
                  <div>
                    <b className="mb-ocr" style={ocrStyle(ocr.price)}>
                      $49
                    </b>
                    <span>per person / month</span>
                  </div>
                </div>
              </div>
              <div className="mb-chart">
                <div className="mb-chart-top">
                  <span>Time back</span>
                  <b>+12 hours</b>
                </div>
                <div className="mb-bars">
                  {[
                    ["M", 25],
                    ["T", 39],
                    ["W", 52],
                    ["T", 71],
                    ["F", 96],
                  ].map(([d, h], i) => (
                    <span key={i} style={{ height: `${h}%` }}>
                      {d}
                    </span>
                  ))}
                </div>
              </div>
            </div>
            {caption ? (
              <div className="mb-caption">
                <span>{caption.who}</span>
                <span className="mb-ocr" style={{ ...ocrStyle(ocr.question), fontSize: 14, color: "#f5f6f8", margin: 0, padding: 0, display: "inline" }}>
                  {caption.text}
                </span>
              </div>
            ) : null}
          </div>
        ) : null}
      </div>
      <div className="mb-controls">
        <span className="mb-callinfo">
          1:14 PM <i /> Your next big thing
        </span>
        <div className="mb-icons">
          <span>
            <svg viewBox="0 0 24 24">
              <rect x="9" y="3" width="6" height="11" rx="3" />
              <path d="M5 11a7 7 0 0 0 14 0M12 18v3" />
            </svg>
          </span>
          <span>
            <svg viewBox="0 0 24 24">
              <rect x="3" y="6" width="12" height="12" rx="3" />
              <path d="m15 10 6-3v10l-6-3" />
            </svg>
          </span>
          <span>CC</span>
          <span>
            <svg viewBox="0 0 24 24">
              <rect x="3" y="4" width="18" height="13" rx="2" />
              <path d="M12 14V8m-3 3 3-3 3 3" />
            </svg>
          </span>
          <span className="mb-hang">
            <svg viewBox="0 0 24 24">
              <path d="M3 15v-4c5-5 13-5 18 0v4l-5-1v-3a10 10 0 0 0-8 0v3z" />
            </svg>
          </span>
        </div>
        <span className="mb-count">2 in call</span>
      </div>
    </div>
  );
};

const MenuBar: React.FC = () => (
  <div className="mb-menubar">
    <div>
      <span style={{ fontSize: 12 }}>●</span>
      <b>Meet</b>
      <span>File</span>
      <span>Edit</span>
      <span>View</span>
      <span>Window</span>
    </div>
    <div>
      <svg width="13" height="10" viewBox="0 0 16 12" fill="none" stroke="#d6dae4" strokeWidth="1.6" strokeLinecap="round">
        <path d="M1.5 4.5a9.5 9.5 0 0 1 13 0M4 7.2a6 6 0 0 1 8 0M6.6 9.8a2.2 2.2 0 0 1 2.8 0" />
      </svg>
      <svg width="20" height="10" viewBox="0 0 24 12">
        <rect x="0.5" y="0.5" width="20" height="11" rx="3" fill="none" stroke="#d6dae4" opacity="0.6" />
        <rect x="2" y="2" width="15" height="8" rx="1.5" fill="#d6dae4" />
        <rect x="21.5" y="4" width="1.6" height="4" rx="0.8" fill="#d6dae4" opacity="0.6" />
      </svg>
      <span>Thu 1:14 PM</span>
    </div>
  </div>
);

/** The device. `screenOverlay` renders above the Meet window, inside the screen (the notch, cursor, effects). */
export const MacBook: React.FC<{ meet: MeetState; screenOverlay: React.ReactNode }> = ({ meet, screenOverlay }) => (
  <div className="mb">
    <style>{css}</style>
    <div className="mb-lid">
      <div className="mb-screen">
        <MenuBar />
        <Meet {...meet} />
        <div className="mb-dock">
          <span style={{ background: "linear-gradient(130deg,#7c9fb7,#50688f)" }} />
          <span style={{ background: "linear-gradient(120deg,#c7899f,#8c6b9e)" }} />
          <span style={{ background: "linear-gradient(120deg,#4caf7a,#2f7d58)" }} />
          <span style={{ background: "linear-gradient(120deg,#cdc6b5,#babaa0)" }} />
          <span style={{ background: "linear-gradient(120deg,#babcc2,#6c707c)" }} />
        </div>
        {screenOverlay}
        <div className="mb-screen-edge" />
      </div>
    </div>
    <div className="mb-base">
      <div />
    </div>
    <div className="mb-shadow" />
  </div>
);
