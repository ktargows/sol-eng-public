library(rgl)
library(rglwidget)
library(htmltools)

theta <- seq(0, 6*pi, len=100)
xyz <- cbind(sin(theta), cos(theta), theta)
lineid <- plot3d(xyz, type="l", alpha = 1:0, 
                 lwd = 5, col = "blue")["data"]

browsable(tagList(
  rglwidget(elementId = "example", width = 500, height = 400,
            controllers = "player"),
  playwidget("example", 
             ageControl(births = theta, ages = c(0, 0, 1),
                        objids = lineid, alpha = c(0, 1, 0)),
             start = 1, stop = 6*pi, step = 0.1, 
             rate = 6,elementId = "player")
))