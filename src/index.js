const express = require('express');
const bodyParser = require('body-parser');

const app = express();
const port = process.env.HTTP_PORT ?? 80;

app.use(bodyParser.json());

app.all('*',(req, res) => {
  console.log({
    date: new Date().toJSON(),
    method: req.method,
    url: req.url,
    params: req.params,
    body: req.body,
  });

  res.send({
    message: process.env.MESSAGE ?? 'undefined',
    uptime: Math.floor(process.uptime()),
  });
})

app.listen(port, () => {
  console.log(`Example app listening on port ${port}`);
});
