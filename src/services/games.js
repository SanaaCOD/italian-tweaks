const { runScript } = require('./script-runner');

const GAME_ACTIONS = {
  blackops7: 'games/Apply-BlackOps7Settings.ps1',
  fortnite: 'games/Apply-FortniteSettings.ps1',
  valorant: 'games/Apply-ValorantSettings.ps1',
  cs2: 'games/Apply-CS2Settings.ps1',
  apex: 'games/Apply-ApexLegendsSettings.ps1',
  tarkov: 'games/Apply-TarkovSettings.ps1',
  rust: 'games/Apply-RustSettings.ps1',
  r6: 'games/Apply-RainbowSixSiegeSettings.ps1',
  battlefield6: 'games/Apply-Battlefield6Settings.ps1',
  marvelrivals: 'games/Apply-MarvelRivalsSettings.ps1',
  lol: 'games/Apply-LeagueOfLegendsSettings.ps1',
  dota2: 'games/Apply-Dota2Settings.ps1',
  fivem: 'games/Apply-FiveMSettings.ps1',
  eafc26: 'games/Apply-EAFC26Settings.ps1',
  overwatch2: 'games/Apply-Overwatch2Settings.ps1',
  marathon: 'games/Apply-MarathonSettings.ps1',
  rocketleague: 'games/Apply-RocketLeagueSettings.ps1',
  arcraiders: 'games/Apply-ArcRaidersSettings.ps1'
};

module.exports = {
  detectWarzonePath: () => runScript('games/Detect-WarzonePath.ps1', [], { read: true }),
  applyWarzoneProfile: () => runScript('games/Apply-WarzoneProfile.ps1'),
  restoreWarzoneProfile: () => runScript('games/Restore-WarzoneProfile.ps1'),
  applyGame: (gameId) => {
    const script = GAME_ACTIONS[gameId];
    if (!script) {
      return Promise.resolve({
        ok: false,
        status: 'error',
        message: `Jeu inconnu: ${gameId}`,
        action: gameId
      });
    }
    return runScript(script);
  },
  listGameScripts: () => Object.keys(GAME_ACTIONS)
};
