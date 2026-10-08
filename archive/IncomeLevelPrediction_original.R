# Author: Esad Kopru
# Comparative analysis of Income level prediction

rm(list=ls(all=TRUE))                        
library(class); library(gmodels)
library(ISLR)
library(e1071)
library(class)


setwd("PathToTheData")

normalize <- function(x) {
  return ((x - min(x)) / (max(x) - min(x)))
}

colNames = c ("age", "workclass", "fnlwgt", "education", 
              "educationnum", "maritalstatus", "occupation",
              "relationship", "race", "sex", "capitalgain",
              "capitalloss", "hoursperweek", "nativecountry",
              "incomelevel")

inc = read.table ("adult2.data", header = FALSE, sep = ",",
                    strip.white = TRUE, col.names = colNames,
                    na.strings = "?", stringsAsFactors = TRUE)

summary(inc)

#inc_clean <- DMwR::knnImputation(inc, k=5, scale=T, meth="weighAve")
#summary(inc_clean)

# scatterplot
car::scatterplotMatrix(~incomelevel+age+educationnum+maritalstatus+occupation, data=inc_clean)
car::scatterplotMatrix(~incomelevel+race+sex+hoursperweek, data=inc_clean)

# Keep values without NAs
inc_clean <- inc[complete.cases(inc), ]
summary(inc_clean)

# income level vs occupation, maritalstatus, race and sex
plot(inc_clean$incomelevel~inc_clean$occupation)
plot(inc_clean$incomelevel~inc_clean$maritalstatus)

plot(inc_clean$incomelevel~inc_clean$race)
plot(inc_clean$incomelevel~inc_clean$sex)


set.seed(12345)
# split training and test datasets
train_sample <- sample(nrow(inc_clean), round(nrow(inc_clean)*0.8))
inc_clean_train <- inc[train_sample, ]
inc_clean_test  <- inc[-train_sample, ]


############
# Logistic regression model

log.base.model <- glm(incomelevel~., data=inc_clean_train, family="binomial")
summary(log.base.model)
vif(log.base.model)

inc_clean <- inc_clean[,-4]
inc_clean_train <- inc_clean_train[,-4]
inc_clean_test <- inc_clean_test[,-4]

log.updated.model <- glm(incomelevel~. ,data=inc_clean_train, family="binomial")
summary(log.updated.model)
vif(log.updated.model)
# High VIF, relationship and marital status

log.updated.model2 <- glm(incomelevel~age+workclass+fnlwgt+educationnum+
                            occupation+relationship+race+sex+capitalgain+capitalloss+
                            hoursperweek, data=inc_clean_train, family="binomial")
summary(log.updated.model2)
vif(log.updated.model2)


####################################
# Tree based classification
tree.incomelevel <- tree(incomelevel~., data=inc_clean_train)

tree.incomelevel <- tree(incomelevel~age+workclass+fnlwgt+educationnum+maritalstatus+
                           occupation+relationship+race+sex+capitalgain+capitalloss+
                           hoursperweek, data=inc_clean)
summary(tree.incomelevel)

plot(tree.incomelevel);text(tree.incomelevel, pretty=0)
tree.incomelevel

## Pruning
cv.incomelevel <- cv.tree(tree.incomelevel, FUN=prune.misclass)
#FUN=prune.tree is for metric variables.
names(cv.incomelevel)
cv.incomelevel

# take the size where deviation is the smallest. here it is 5
plot(cv.incomelevel$size, cv.incomelevel$dev, type="b")

plot(cv.incomelevel$k, cv.incomelevel$dev, type="b")

prune.incomelevel <- prune.misclass(tree.incomelevel, best=5)
plot(prune.incomelevel); text(prune.incomelevel, pretty=0)

summary(prune.incomelevel)


####################################
# Random forest classification
# native country has more than 32 levels that random forest function does not work. 
# So, exclude native country

rf.incomelevel <- randomForest(incomelevel~., data=inc_clean, importance=TRUE)
importance(rf.incomelevel)

######### Tune Random Forest ###########
mtry <- tuneRF(inc_clean_train, inc_clean_train$incomelevel, ntreeTry=10,
               stepFactor=1.5,improve=TRUE, trace=TRUE, plot=TRUE, doBest=TRUE)


rf2.incomelevel <- randomForest(incomelevel~., data=inc_clean_train, mtry=4, importance=TRUE)
rf2.incomelevel
varImpPlot(rf2.incomelevel)

###########################################################
######################
######## SVM

svm.fit <- svm(incomelevel~.,data=inc_clean_train, cost=0.01, kernel='linear')
summary(svm.fit)

svm.pred <- predict(svm.fit,inc_clean_test)
table(inc_clean_test$incomelevel,svm.pred)
mean(inc_clean_test$incomelevel != svm.pred)


######## Linear SVM Tune
svm.tune <- tune(svm, incomelevel ~ ., data = inc_clean_train, 
                 kernel = "linear", ranges = list(cost = 10^seq(-1,1, by = 0.25)))
summary(svm.tune)


# Author: Esad Kopru
# Comparative analysis of Income level prediction

######### Evaluation ###########

# 1 - Logistic Regression
predictLogit <- predict(log.updated.model2, inc_clean_test)
results <- ifelse(predictLogit > 0.5,'>50K','<=50K')


CrossTable(inc_clean_test$incomelevel, results,
           prop.chisq = FALSE, prop.c = FALSE, prop.r = TRUE, prop.t = TRUE,
           dnn = c('actual incLevel', 'predicted incLevel'))


library(ROSE)
roc.curve(inc_clean_test$incomelevel, predictLogit)


# 2 - Classification Tree
tree.pred <- predict(prune.incomelevel, newdata=inc_clean_test, type="class") 
# if we use prob rather than class, that would be the probability.
# rookcurves , it is important to use type="prob".
CrossTable(inc_clean_test$incomelevel, tree.pred,
           prop.chisq = FALSE, prop.c = FALSE, prop.r = TRUE, prop.t = FALSE,
           dnn = c('actual default', 'predicted default'))


# 3 - Random forest with ntree
rf.predict1 <-  predict(rf.incomelevel, newdata=inc_clean_test)

CrossTable(inc_clean_test$incomelevel, rf.predict1,
           prop.chisq = FALSE, prop.c = FALSE, prop.r = TRUE, prop.t = FALSE,
           dnn = c('actual default', 'predicted default'))

# 4 - Random forest with mtry
rf.predict2 <-  predict(rf2.incomelevel, newdata=inc_clean_test)

CrossTable(inc_clean_test$incomelevel, rf.predict2,
           prop.chisq = FALSE, prop.c = FALSE, prop.r = TRUE, prop.t = FALSE,
           dnn = c('actual default', 'predicted default'))


# 5 - Linear SVM
svm.pred <- predict(svm.fit,inc_clean_test)
table(inc_clean_test$incomelevel,svm.pred)
mean(inc_clean_test$incomelevel != svm.pred)


CrossTable(inc_clean_test$incomelevel, svm.pred,
           prop.chisq = FALSE, prop.c = FALSE, prop.r = TRUE, prop.t = FALSE,
           dnn = c('actual default', 'predicted default'))


# 6 - Linear SVM  Tuned

svm.pred <- predict(svm.tune$best.model,inc_clean_test)
table(inc_clean_test$incomelevel,svm.pred)
mean(inc_clean_test$incomelevel != svm.pred)


CrossTable(inc_clean_test$incomelevel, svm.pred,
           prop.chisq = FALSE, prop.c = FALSE, prop.r = TRUE, prop.t = FALSE,
           dnn = c('actual default', 'predicted default'))

roc.curve(inc_clean_test$incomelevel, svm.pred)

# Author: Esad Kopru
# Comparative analysis of Income level prediction