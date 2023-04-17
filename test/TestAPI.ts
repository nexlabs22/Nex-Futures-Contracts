const axios = require("axios");

const options = {
  method: 'GET',
  url: 'https://api-football-v1.p.rapidapi.com/v3/fixtures/headtohead',
  params: {h2h: '33-34', from: '2023-01-01', to: '2023-03-29'},
  headers: {
    'X-RapidAPI-Key': 'MY-API-KEY',
    'X-RapidAPI-Host': 'api-football-v1.p.rapidapi.com'
  }
};

axios.request(options).then(function (response:any) {
	console.log(response.data.response[0].score.fulltime.home);
}).catch(function (error:any) {
	console.error(error);
});