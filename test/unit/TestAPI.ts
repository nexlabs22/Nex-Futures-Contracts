const axios = require("axios");
require('dotenv').config();

const options = {
  method: 'GET',
  url: 'https://app.nexlabs.io/api/footballH2H',
  // params: {h2h: '33-34', from: '2023-01-01', to: '2023-03-29'},
  // headers: {
  //   'X-RapidAPI-Key': 'MY-API-KEY',
  //   'X-RapidAPI-Host': 'api-football-v1.p.rapidapi.com'
  // }
};

axios.request(options).then(function (result:any) {
  
	console.log("home :", result.data.response[0].goals.home);
	console.log("away :", result.data.response[0].goals.away);
}).catch(function (error:any) {
	console.error(error);
});